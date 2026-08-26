import Foundation

public enum AccountType: String, Codable, CaseIterable, Identifiable {
    case xtream = "Xtream Codes API"
    case m3u = "M3U / M3U8 Bağlantısı"

    public var id: String { rawValue }
}

public struct Account: Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var type: AccountType
    public var serverUrl: String
    public var username: String
    public var password: String
    public var m3uUrl: String
    public var createdAt: Date
    public var lastUpdated: Date?
    public var expiryDate: Date?
    public var maxConnections: String?
    public var serverProtocol: String?
    public var isConnected: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: AccountType,
        serverUrl: String = "",
        username: String = "",
        password: String = "",
        m3uUrl: String = "",
        createdAt: Date = Date(),
        lastUpdated: Date? = nil,
        expiryDate: Date? = nil,
        maxConnections: String? = nil,
        serverProtocol: String? = nil,
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.serverUrl = serverUrl
        self.username = username
        self.password = password
        self.m3uUrl = m3uUrl
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.expiryDate = expiryDate
        self.maxConnections = maxConnections
        self.serverProtocol = serverProtocol
        self.isConnected = isConnected
    }
}
