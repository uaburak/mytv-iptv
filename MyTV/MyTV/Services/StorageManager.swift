import Foundation
import Combine

@MainActor
public final class StorageManager: ObservableObject {
    public static let shared = StorageManager()

    private let accountsKey = "mytv_saved_accounts"
    private let activeAccountIdKey = "mytv_active_account_id"
    private let favoritesKey = "mytv_favorite_ids"

    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var activeAccount: Account?
    @Published public private(set) var favorites: Set<String> = []

    private init() {
        loadAccounts()
        loadFavorites()
    }

    // MARK: - Accounts Management

    public func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: accountsKey),
           let list = try? JSONDecoder().decode([Account].self, from: data) {
            self.accounts = list
        } else {
            self.accounts = []
        }

        if let activeId = UserDefaults.standard.string(forKey: activeAccountIdKey),
           let found = accounts.first(where: { $0.id == activeId }) {
            self.activeAccount = found
        } else {
            self.activeAccount = accounts.first
        }
    }

    public func saveAccount(_ account: Account) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }
        persistAccounts()
        setActiveAccount(account)
    }

    public func setActiveAccount(_ account: Account?) {
        self.activeAccount = account
        UserDefaults.standard.set(account?.id, forKey: activeAccountIdKey)
    }

    public func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        persistAccounts()
        if activeAccount?.id == id {
            setActiveAccount(accounts.first)
        }
    }

    // MARK: - Favorites Management

    public func loadFavorites() {
        let list = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        self.favorites = Set(list)
    }

    public func isFavorite(id: String) -> Bool {
        favorites.contains(id)
    }

    public func toggleFavorite(id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    // MARK: - Clear All

    public func clearAll() {
        accounts.removeAll()
        activeAccount = nil
        favorites.removeAll()
        UserDefaults.standard.removeObject(forKey: accountsKey)
        UserDefaults.standard.removeObject(forKey: activeAccountIdKey)
        UserDefaults.standard.removeObject(forKey: favoritesKey)
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }
}
