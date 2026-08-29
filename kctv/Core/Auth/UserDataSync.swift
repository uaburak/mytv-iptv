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
        let existing = try await collection.getDocuments()
        let keep = Set(ids.map { Self.documentID(for: $0) })

        let batch = database.batch()
        for document in existing.documents where !keep.contains(document.documentID) {
            batch.deleteDocument(document.reference)
        }
        for id in ids {
            let data = try Firestore.Encoder().encode(id)
            batch.setData(data, forDocument: collection.document(Self.documentID(for: id)), merge: false)
        }
        try await batch.commit()
    }

    private func loadIDs(in collectionName: String) async throws -> [MediaID] {
        let snapshot = try await userDocument.collection(collectionName).getDocuments()
        return snapshot.documents.compactMap { document in
            if let id = try? document.data(as: MediaID.self) { return id }
            // Eski kayıtlar içeriğin tamamını tutuyordu; kimliği içinden alıp
            // devam ediyoruz. Bir sonraki yazmada belge yeni biçime dönüyor.
            return try? document.data(as: MediaItem.self).id
        }
    }

    func saveProgress(_ entries: [PlaybackProgress]) async throws {
        let collection = userDocument.collection("progress")
        let batch = database.batch()
        // Yalnızca en son 50 kayıt senkronlanıyor; gerisi cihazda kalır.
        for entry in entries.prefix(50) {
            let data = try Firestore.Encoder().encode(entry)
            batch.setData(data, forDocument: collection.document(Self.safeID(entry.id)), merge: true)
        }
        try await batch.commit()
    }

    func loadProgress() async throws -> [PlaybackProgress] {
        let snapshot = try await userDocument.collection("progress").getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: PlaybackProgress.self) }
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
