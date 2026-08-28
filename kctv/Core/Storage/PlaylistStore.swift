import Foundation
import Observation

/// Kullanıcının kaynak listelerini yönetir.
/// Metadata cihazda JSON, şifreler Keychain'de; oturum açıksa metadata ayrıca
/// Firestore'a yazılır (bkz. `UserDataSync`).
@MainActor
@Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    var selectedPlaylistID: String?

    private let store = LocalStore(folder: "playlists")
    private let key = "playlists"
    private let selectionKey = "kctv.selectedPlaylist"

    var selected: Playlist? {
        playlists.first { $0.id == selectedPlaylistID } ?? playlists.first
    }

    var hasPlaylists: Bool { !playlists.isEmpty }

    init() {
        playlists = store.read([Playlist].self, key: key) ?? []
        selectedPlaylistID = UserDefaults.standard.string(forKey: selectionKey) ?? playlists.first?.id
    }

    func add(_ playlist: Playlist, secret: String?) {
        if let secret, !secret.isEmpty {
            KeychainStore.save(secret, for: playlist.secretKey)
        }
        playlists.removeAll { $0.id == playlist.id }
        playlists.append(playlist)
        selectedPlaylistID = playlist.id
        persist()
    }

    func update(_ playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index] = playlist
        persist()
    }

    func remove(_ playlist: Playlist) {
        KeychainStore.delete(playlist.secretKey)
        playlists.removeAll { $0.id == playlist.id }
        if selectedPlaylistID == playlist.id {
            selectedPlaylistID = playlists.first?.id
        }
        persist()
    }

    func select(_ playlist: Playlist) {
        selectedPlaylistID = playlist.id
        persist()
    }

    func secret(for playlist: Playlist) -> String? {
        KeychainStore.read(playlist.secretKey)
    }

    /// Firestore'dan gelen listeleri yereldekiyle birleştirir.
    /// Şifreler buluta gitmediği için yalnızca metadata güncellenir.
    func merge(remote: [Playlist]) {
        var merged = playlists
        for playlist in remote where !merged.contains(where: { $0.id == playlist.id }) {
            merged.append(playlist)
        }
        playlists = merged.sorted { $0.createdAt < $1.createdAt }
        if selectedPlaylistID == nil { selectedPlaylistID = playlists.first?.id }
        persist()
    }

    private func persist() {
        store.write(playlists, key: key)
        UserDefaults.standard.set(selectedPlaylistID, forKey: selectionKey)
    }
}
