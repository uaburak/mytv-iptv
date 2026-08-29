import AuthenticationServices
import Foundation

extension Notification.Name {
    static let appModelPhaseDidChange = Notification.Name("kctv.phaseDidChange")
    static let appModelPlaybackDidChange = Notification.Name("kctv.playbackDidChange")
    static let appModelAuthDidChange = Notification.Name("kctv.authDidChange")
    static let appModelFavoritesDidChange = Notification.Name("kctv.favoritesDidChange")
    /// Katalog yüklendi/değişti; listeler kendini yeniler.
    static let contentLibraryDidChange = Notification.Name("kctv.libraryDidChange")
}

/// Uygulamanın hangi ana aşamada olduğu.
enum AppPhase: Equatable {
    case launching
    case signedOut
    /// Oturum açık ama henüz liste eklenmemiş.
    case needsPlaylist
    case ready
}

private let guestModeDefaultsKey = "kctv.isGuest"

/// Oturum, listeler, katalog ve senkronu bir arada tutan üst seviye durum.
///
/// SwiftUI'daki `@Observable` yerine `NotificationCenter` kullanıyor: UIKit
/// görünüm denetleyicileri değişimleri bildirimle dinliyor.
@MainActor
final class AppModel {
    private(set) var phase: AppPhase = .launching {
        didSet {
            guard phase != oldValue else { return }
            NotificationCenter.default.post(name: .appModelPhaseDidChange, object: nil)
        }
    }

    private(set) var user: AuthUser?
    private(set) var authError: String?
    private(set) var isAuthenticating = false

    /// Hesap açmadan devam eden kullanıcı. Seçim kalıcı: misafir olarak liste
    /// ekleyen kullanıcı her açılışta giriş ekranına düşmemeli.
    private(set) var isGuest = UserDefaults.standard.bool(forKey: guestModeDefaultsKey) {
        didSet { UserDefaults.standard.set(isGuest, forKey: guestModeDefaultsKey) }
    }

    let playlists = PlaylistStore()
    let activity = UserActivityStore()
    let library: ContentLibrary

    /// Player açılması istendiğinde dolar; `RootViewController` bunu tüketir.
    var playback: PlaybackContext? {
        didSet {
            guard playback != nil else { return }
            NotificationCenter.default.post(name: .appModelPlaybackDidChange, object: nil)
        }
    }

    private(set) var playbackError: String?

    private let auth: any AuthService
    private var sync: UserDataSync?

    init(auth: any AuthService) {
        self.auth = auth
        self.library = ContentLibrary(activity: activity)
        self.activity.onChange = { [weak self] favorites, watchlist, progress in
            NotificationCenter.default.post(name: .appModelFavoritesDidChange, object: nil)
            self?.pushActivity(favorites: favorites, watchlist: watchlist, progress: progress)
        }
        self.library.onChange = {
            NotificationCenter.default.post(name: .contentLibraryDidChange, object: nil)
        }
    }

    // MARK: - Açılış

    func start() async {
        if let user = await auth.restoreSession() {
            await handleSignedIn(user)
        } else if isGuest {
            await refreshPhase()
        } else {
            phase = .signedOut
        }
    }

    // MARK: - Giriş

    /// Apple butonunun sonucunu Firebase'in beklediği parçalara ayırır.
    func handleAppleAuthorization(_ result: Result<ASAuthorization, any Error>, rawNonce: String?) async {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce
            else {
                setAuthError("Apple kimlik doğrulama yanıtı okunamadı.")
                return
            }
            await performSignIn {
                try await self.auth.signInWithApple(
                    idToken: idToken,
                    rawNonce: rawNonce,
                    fullName: credential.fullName
                )
            }
        case let .failure(error):
            // Kullanıcı vazgeçtiyse uyarı göstermiyoruz.
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            setAuthError(error.localizedDescription)
        }
    }

    func signInWithGoogle() async {
        await performSignIn { try await self.auth.signInWithGoogle() }
    }

    private func performSignIn(_ operation: @escaping () async throws -> AuthUser) async {
        isAuthenticating = true
        authError = nil
        NotificationCenter.default.post(name: .appModelAuthDidChange, object: nil)
        defer {
            isAuthenticating = false
            NotificationCenter.default.post(name: .appModelAuthDidChange, object: nil)
        }
        do {
            let user = try await operation()
            await handleSignedIn(user)
        } catch AuthError.cancelled {
            // Kullanıcı vazgeçti.
        } catch {
            setAuthError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func setAuthError(_ message: String?) {
        authError = message
        NotificationCenter.default.post(name: .appModelAuthDidChange, object: nil)
    }

    func signOut() {
        try? auth.signOut()
        user = nil
        sync = nil
        isGuest = false
        phase = .signedOut
    }

    /// Geliştirici işlemi: Cihazda tutulan tüm yerel verileri (önbellek, keychain,
    /// yerel listeler, ilerleme ve tercihler) temizler, oturumu kapatır ve uygulamayı
    /// ilk kurulum haline getirir. Firestore verilerine dokunmaz.
    func resetAllLocalData() {
        try? auth.signOut()
        user = nil
        sync = nil
        isGuest = false
        playlists.clearAll()
        activity.clearAll()
        library.reset()
        LocalStore.deleteAllKCTVData()
        KeychainStore.deleteAll()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        URLCache.shared.removeAllCachedResponses()
        NotificationCenter.default.post(name: .appModelFavoritesDidChange, object: nil)
        NotificationCenter.default.post(name: .contentLibraryDidChange, object: nil)
        phase = .signedOut
    }

    private func handleSignedIn(_ user: AuthUser) async {
        self.user = user
        isGuest = false
        self.sync = UserDataSync(uid: user.uid)
        await pullRemoteData(for: user)
        await refreshPhase()
    }

    /// Uzaktaki listeleri/favorileri çekip yereldekiyle birleştirir.
    /// Ağ yoksa sessizce yerelle devam edilir.
    private func pullRemoteData(for user: AuthUser) async {
        guard let sync else { return }
        try? await sync.saveProfile(user)

        async let remotePlaylists = try? await sync.loadPlaylists()
        async let remoteFavorites = try? await sync.loadFavorites()
        async let remoteWatchlist = try? await sync.loadWatchlist()
        async let remoteProgress = try? await sync.loadProgress()

        if let playlistsFromCloud = await remotePlaylists {
            playlists.merge(remote: playlistsFromCloud)
        }
        let favorites = await remoteFavorites
        let watchlist = await remoteWatchlist
        let progress = await remoteProgress
        activity.merge(
            favorites: favorites ?? [],
            watchlist: watchlist ?? [],
            progress: progress ?? []
        )
    }

    private func pushActivity(
        favorites: [MediaID],
        watchlist: [MediaID],
        progress: [PlaybackProgress]
    ) {
        guard let sync else { return }
        Task {
            try? await sync.saveFavorites(favorites)
            try? await sync.saveWatchlist(watchlist)
            try? await sync.saveProgress(progress)
        }
    }

    // MARK: - Listeler

    func refreshPhase() async {
        guard user != nil || isGuest else { phase = .signedOut; return }

        // Uygulamada gömülü içerik yok; liste yoksa kullanıcı liste ekler.
        guard let playlist = playlists.selected else {
            phase = .needsPlaylist
            return
        }

        phase = .ready
        await library.connect(to: playlist, secret: playlists.secret(for: playlist))
    }

    func addPlaylist(_ playlist: Playlist, secret: String?) async {
        playlists.add(playlist, secret: secret)
        if let sync {
            Task { try? await sync.savePlaylists(self.playlists.playlists) }
        }
        await refreshPhase()
    }

    func removePlaylist(_ playlist: Playlist) async {
        playlists.remove(playlist)
        if let sync {
            Task { try? await sync.deletePlaylist(id: playlist.id) }
        }
        await refreshPhase()
    }

    func selectPlaylist(_ playlist: Playlist) async {
        playlists.select(playlist)
        await refreshPhase()
    }

    /// Giriş ekranındaki "giriş yapmadan devam et". Cihazda kayıtlı liste
    /// varsa onunla açılır, yoksa liste ekleme ekranına gider.
    func continueAsGuest() async {
        isGuest = true
        await refreshPhase()
    }

    // MARK: - Oynatma

    func play(_ item: MediaItem) async {
        do {
            playback = try await library.playback(for: item)
        } catch {
            playbackError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func play(_ episode: Episode, in series: MediaItem) async {
        do {
            playback = try await library.playback(for: episode, in: series)
        } catch {
            playbackError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Oynatılan bölümden sonraki bölüm.
    ///
    /// Sezonlar sırayla düzleştiriliyor: sezonun son bölümünden sonra bir
    /// sonraki sezonun ilk bölümü geliyor. Dizi değilse veya son bölümdeyse
    /// `nil` dönüyor.
    func nextEpisode(after context: PlaybackContext) async -> (episode: Episode, series: MediaItem)? {
        guard let (mediaID, episodeID) = Self.decode(contextID: context.id),
              mediaID.kind == .series,
              let episodeID,
              let series = library.item(for: mediaID),
              let detail = try? await library.detail(for: series)
        else { return nil }

        let episodes = detail.seasons.flatMap(\.episodes)
        guard let index = episodes.firstIndex(where: { $0.id == episodeID }),
              episodes.indices.contains(index + 1)
        else { return nil }

        return (episodes[index + 1], detail.item)
    }

    /// Context kimliği "source|kind|raw#episodeID" biçiminde.
    private static func decode(contextID: String) -> (MediaID, String?)? {
        let parts = contextID.split(separator: "#", maxSplits: 1).map(String.init)
        let mediaParts = parts[0].split(separator: "|", maxSplits: 2).map(String.init)
        guard mediaParts.count == 3, let kind = MediaKind(rawValue: mediaParts[1]) else { return nil }
        return (MediaID(source: mediaParts[0], kind: kind, raw: mediaParts[2]), parts.count > 1 ? parts[1] : nil)
    }

    func recordProgress(for context: PlaybackContext, position: Double, duration: Double) {
        guard let (mediaID, episodeID) = Self.decode(contextID: context.id) else { return }
        activity.record(
            mediaID: mediaID,
            episodeID: episodeID,
            position: position,
            duration: duration
        )
    }
}
