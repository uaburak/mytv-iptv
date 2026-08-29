import Foundation
import FirebaseFirestore

/// Kullanıcı verisinin Firestore ayağı.
///
/// Şema:
///   users/{uid}                       -> profil
///   users/{uid}/playlists/{id}        -> liste metadata'sı (şifre YOK)
///   users/{uid}/favorites/{mediaID}   -> favoriler (yalnızca kimlik)
///   users/{uid}/watchlist/{mediaID}   -> izleme listesi (yalnızca kimlik)
///   users/{uid}/progress/{id}         -> izlemeyi sürdür
///
/// Favori ve izleme listesi belgelerinde içeriğin tamamı değil yalnızca
/// `MediaID` duruyor: sağlayıcı kimliği, tür ve ham `stream_id`/`series_id`.
///
/// Şifreler bilinçli olarak buluta gitmiyor; yalnızca cihazın Keychain'inde.
/// Bu yüzden yeni bir cihazda liste görünür ama şifre bir kez sorulur.
actor UserDataSync {
    private let database = Firestore.firestore()
    private let uid: String

    /// Buluta en son yazılmış belge kimlikleri, koleksiyon adına göre.
    ///
    /// Bu olmadan her kayıt koleksiyonun tamamını okuyup tamamını yeniden
    /// yazıyordu: 200 favorili bir kullanıcıda tek kalp dokunuşu 200'den
    /// fazla belge yazması demekti. Girişte `loadIDs` bu haritayı zaten
    /// dolduruyor, dolayısıyla çoğu oturumda ek okuma da yok.
    private var syncedIDs: [String: Set<String>] = [:]

    /// Buluta en son yazılmış ilerleme kayıtları; değişmeyen kayıt yeniden
    /// yazılmıyor.
    private var syncedProgress: [String: PlaybackProgress] = [:]

    init(uid: String) {
        self.uid = uid
    }

    private var userDocument: DocumentReference {
        database.collection("users").document(uid)
    }

    func saveProfile(_ user: AuthUser) async throws {
        try await userDocument.setData([
            "uid": user.uid,
            "displayName": user.displayName as Any,
            "email": user.email as Any,
            "providerID": user.providerID as Any,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }

    // MARK: - Listeler

    func savePlaylists(_ playlists: [Playlist]) async throws {
        let collection = userDocument.collection("playlists")
        let batch = database.batch()
        for playlist in playlists {
            let data = try Firestore.Encoder().encode(playlist)
            batch.setData(data, forDocument: collection.document(playlist.id), merge: true)
        }
        try await batch.commit()
    }

    func deletePlaylist(id: String) async throws {
        try await userDocument.collection("playlists").document(id).delete()
    }

    func loadPlaylists() async throws -> [Playlist] {
        let snapshot = try await userDocument.collection("playlists").getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Playlist.self) }
    }

    // MARK: - Favoriler ve ilerleme

    func saveFavorites(_ ids: [MediaID]) async throws {
        try await saveIDs(ids, in: "favorites")
    }

    func loadFavorites() async throws -> [MediaID] {
        try await loadIDs(in: "favorites")
    }

    func saveWatchlist(_ ids: [MediaID]) async throws {
        try await saveIDs(ids, in: "watchlist")
    }

    func loadWatchlist() async throws -> [MediaID] {
        try await loadIDs(in: "watchlist")
    }

    /// Buluta yalnızca içerik kimliği yazılıyor — sağlayıcının `stream_id` /
    /// `series_id` değeri, türü ve hangi listeden geldiği. Başlık, afiş ve
    /// künye içeriğin kendi verisi; katalogdan çözülüyor.
    private func saveIDs(_ ids: [MediaID], in collectionName: String) async throws {
        let collection = userDocument.collection(collectionName)
        let desired = Dictionary(
            ids.map { (Self.documentID(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Bilinen durum yoksa (bu oturumda hiç okunmadıysa) bir kez okunuyor.
        let known: Set<String>
        if let cached = syncedIDs[collectionName] {
            known = cached
        } else {
            known = Set(try await collection.getDocuments().documents.map(\.documentID))
        }

        let target = Set(desired.keys)
        let removed = known.subtracting(target)
        let added = target.subtracting(known)

        guard !removed.isEmpty || !added.isEmpty else {
            syncedIDs[collectionName] = target
            return
        }

        let batch = database.batch()
        for documentID in removed {
            batch.deleteDocument(collection.document(documentID))
        }
        for documentID in added {
            guard let id = desired[documentID] else { continue }
            let data = try Firestore.Encoder().encode(id)
            batch.setData(data, forDocument: collection.document(documentID), merge: false)
        }
        try await batch.commit()
        // Yalnızca yazma başarılıysa güncelleniyor; hata durumunda bir
        // sonraki denemede fark yeniden hesaplanıyor.
        syncedIDs[collectionName] = target
    }

    private func loadIDs(in collectionName: String) async throws -> [MediaID] {
        let snapshot = try await userDocument.collection(collectionName).getDocuments()
        // Fark hesabının başlangıç noktası; ilk yazmada ek okuma gerekmiyor.
        syncedIDs[collectionName] = Set(snapshot.documents.map(\.documentID))
        return snapshot.documents.compactMap { document in
            if let id = try? document.data(as: MediaID.self) { return id }
            // Eski kayıtlar içeriğin tamamını tutuyordu; kimliği içinden alıp
            // devam ediyoruz. Bir sonraki yazmada belge yeni biçime dönüyor.
            return try? document.data(as: MediaItem.self).id
        }
    }

    func saveProgress(_ entries: [PlaybackProgress]) async throws {
        // Yalnızca en son 50 kayıt senkronlanıyor; gerisi cihazda kalır.
        // Bunların da yalnızca değişmiş olanları yazılıyor: favori dokunuşu
        // da bu yolu tetikliyor ve ilerleme çoğu zaman aynı kalıyor.
        let changed = entries.prefix(50).filter { syncedProgress[$0.id] != $0 }
        guard !changed.isEmpty else { return }

        let collection = userDocument.collection("progress")
        let batch = database.batch()
        for entry in changed {
            let data = try Firestore.Encoder().encode(entry)
            batch.setData(data, forDocument: collection.document(Self.safeID(entry.id)), merge: true)
        }
        try await batch.commit()
        for entry in changed { syncedProgress[entry.id] = entry }
    }

    func loadProgress() async throws -> [PlaybackProgress] {
        let snapshot = try await userDocument.collection("progress").getDocuments()
        let entries = snapshot.documents.compactMap { try? $0.data(as: PlaybackProgress.self) }
        syncedProgress = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries
    }

    // MARK: - Yardımcılar

    /// Firestore döküman kimliğinde "/" kullanılamaz.
    private static func documentID(for id: MediaID) -> String {
        safeID(id.description)
    }

    private static func safeID(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "#", with: "-")
        return String(cleaned.prefix(1_000))
    }
}
