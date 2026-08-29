import Foundation

/// Son aramalar. Yalnızca cihazda tutuluyor; arama metni kişisel olabildiği
/// için buluta gönderilmiyor.
@MainActor
final class RecentSearchStore {
    private(set) var queries: [String] = []

    private let store = LocalStore(folder: "search")
    private let key = "recent"
    private static let limit = 10

    init() {
        queries = store.read([String].self, key: key) ?? []
    }

    /// Arama sonuca ulaştığında çağrılıyor; her tuş vuruşu kaydedilmiyor.
    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        // Büyük/küçük harf farkı ayrı kayıt saymıyor; en son yazım kazanıyor.
        queries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        queries.insert(trimmed, at: 0)
        if queries.count > Self.limit {
            queries.removeLast(queries.count - Self.limit)
        }
        store.write(queries, key: key)
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        store.write(queries, key: key)
    }

    func clear() {
        queries.removeAll()
        store.write(queries, key: key)
    }
}
