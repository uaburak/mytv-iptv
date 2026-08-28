import Foundation

// Xtream sunucuları aynı alanı sağlayıcıdan sağlayıcıya sayı, metin ya da null
// olarak döndürüyor ("rating": 7.5 / "7.5" / "" / null). Aşağıdaki sarmalayıcılar
// tek bir alanın bütün bu biçimlerini sessizce kabul eder; tek bir tip uyuşmazlığı
// yüzünden 20 bin satırlık listenin tamamının çözümlenememesini engeller.

@propertyWrapper
struct LooseInt: Codable, Hashable, Sendable {
    var wrappedValue: Int?

    init(wrappedValue: Int?) { self.wrappedValue = wrappedValue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { wrappedValue = nil; return }
        if let value = try? container.decode(Int.self) { wrappedValue = value; return }
        if let value = try? container.decode(Double.self) { wrappedValue = Int(value); return }
        if let value = try? container.decode(Bool.self) { wrappedValue = value ? 1 : 0; return }
        if let text = try? container.decode(String.self) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            wrappedValue = Int(trimmed) ?? Double(trimmed).map(Int.init)
            return
        }
        wrappedValue = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try wrappedValue.map { try container.encode($0) } ?? container.encodeNil()
    }
}

@propertyWrapper
struct LooseDouble: Codable, Hashable, Sendable {
    var wrappedValue: Double?

    init(wrappedValue: Double?) { self.wrappedValue = wrappedValue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { wrappedValue = nil; return }
        if let value = try? container.decode(Double.self) { wrappedValue = value; return }
        if let value = try? container.decode(Int.self) { wrappedValue = Double(value); return }
        if let text = try? container.decode(String.self) {
            wrappedValue = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
            return
        }
        wrappedValue = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try wrappedValue.map { try container.encode($0) } ?? container.encodeNil()
    }
}

@propertyWrapper
struct LooseString: Codable, Hashable, Sendable {
    var wrappedValue: String?

    init(wrappedValue: String?) { self.wrappedValue = wrappedValue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { wrappedValue = nil; return }
        if let value = try? container.decode(String.self) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            wrappedValue = trimmed.isEmpty ? nil : trimmed
            return
        }
        if let value = try? container.decode(Int.self) { wrappedValue = String(value); return }
        if let value = try? container.decode(Double.self) { wrappedValue = String(value); return }
        if let value = try? container.decode(Bool.self) { wrappedValue = value ? "1" : "0"; return }
        wrappedValue = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try wrappedValue.map { try container.encode($0) } ?? container.encodeNil()
    }
}

@propertyWrapper
struct LooseStringList: Codable, Hashable, Sendable {
    var wrappedValue: [String]

    init(wrappedValue: [String]) { self.wrappedValue = wrappedValue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { wrappedValue = []; return }
        if let values = try? container.decode([String].self) {
            wrappedValue = values.compactMap {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return
        }
        if let value = try? container.decode(String.self), !value.isEmpty {
            wrappedValue = [value]
            return
        }
        wrappedValue = []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

// Anahtar hiç gelmediğinde de sarmalayıcıların boş değerle kurulmasını sağlar.
extension KeyedDecodingContainer {
    func decode(_ type: LooseInt.Type, forKey key: Key) throws -> LooseInt {
        try decodeIfPresent(type, forKey: key) ?? LooseInt(wrappedValue: nil)
    }

    func decode(_ type: LooseDouble.Type, forKey key: Key) throws -> LooseDouble {
        try decodeIfPresent(type, forKey: key) ?? LooseDouble(wrappedValue: nil)
    }

    func decode(_ type: LooseString.Type, forKey key: Key) throws -> LooseString {
        try decodeIfPresent(type, forKey: key) ?? LooseString(wrappedValue: nil)
    }

    func decode(_ type: LooseStringList.Type, forKey key: Key) throws -> LooseStringList {
        try decodeIfPresent(type, forKey: key) ?? LooseStringList(wrappedValue: [])
    }
}

extension Array {
    /// Boş diziyi nil'e çevirir; "yeni veri boşsa eskisini koru" kalıbı için.
    var nilIfEmptyList: [Element]? { isEmpty ? nil : self }
}

enum LooseParse {
    /// Xtream tarihleri epoch saniye ("1600000000") ya da "2020-01-31" biçiminde gelir.
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let epoch = Double(text), epoch > 0 {
            return Date(timeIntervalSince1970: epoch)
        }
        return isoDayFormatter.date(from: String(text.prefix(10)))
    }

    static func url(_ text: String?) -> URL? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("//") { text = "https:" + text }
        guard text.lowercased().hasPrefix("http") else { return nil }
        return URL(string: text) ?? URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }

    /// "Aksiyon, Macera / Dram" gibi tek satırlık tür alanlarını böler.
    static func genres(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text
            .components(separatedBy: CharacterSet(charactersIn: ",/|;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func year(from text: String?) -> Int? {
        guard let text else { return nil }
        if let year = Int(text), (1900...2100).contains(year) { return year }
        guard let match = text.range(of: "(19|20)\\d{2}", options: .regularExpression) else { return nil }
        return Int(text[match])
    }

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
