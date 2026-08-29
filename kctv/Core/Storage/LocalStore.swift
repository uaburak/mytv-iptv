import Foundation

/// Codable değerleri Application Support altında JSON olarak saklar.
/// Liste anlık görüntüleri on binlerce kayıt olabildiği için UserDefaults yerine
/// dosya kullanıyoruz; UserDefaults bu boyutta belleği kalıcı şişirir.
/// Kodlayıcılar saklanmıyor, çağrı başına üretiliyor: `JSONEncoder` Sendable
/// değil ve bu tip artık arka plan görevlerine geçiriliyor. Kodlayıcı üretmenin
/// bedeli, on binlerce kaydı kodlamanın yanında ölçülemeyecek kadar küçük.
struct LocalStore: Sendable {
    private let directory: URL

    init(folder: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        directory = base.appendingPathComponent("KCTV/\(folder)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func deleteAllKCTVData() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("KCTV", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    /// Anlık görüntünün yaşı; yenileme kararı buna göre veriliyor.
    func age(key: String) -> TimeInterval? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: key).path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(modified)
    }

    private func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }
}
