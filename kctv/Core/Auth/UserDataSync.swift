import Foundation
import FirebaseFirestore

/// Kullanıcı verisinin Firestore ayağı.
///
/// Şema:
///   users/{uid}                       -> profil
///   users/{uid}/playlists/{id}        -> liste metadata'sı (şifre YOK)
///   users/{uid}/favorites/{mediaID}   -> favoriler
///   users/{uid}/progress/{id}         -> izlemeyi sürdür
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

    func saveFavorites(_ items: [MediaItem]) async throws {
        let collection = userDocument.collection("favorites")
        let existing = try await collection.getDocuments()
        let keep = Set(items.map { Self.documentID(for: $0.id) })

        let batch = database.batch()
        for document in existing.documents where !keep.contains(document.documentID) {
            batch.deleteDocument(document.reference)
        }
        for item in items {
            let data = try Firestore.Encoder().encode(item)
            batch.setData(data, forDocument: collection.document(Self.documentID(for: item.id)), merge: true)
        }
        try await batch.commit()
    }

    func loadFavorites() async throws -> [MediaItem] {
        let snapshot = try await userDocument.collection("favorites").getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: MediaItem.self) }
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
