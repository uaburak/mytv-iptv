import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // MARK: - Published Data
    @Published public private(set) var channels: [Channel] = []
    @Published public private(set) var liveCategories: [MediaCategory] = []

    @Published public private(set) var movies: [VODItem] = []
    @Published public private(set) var vodCategories: [MediaCategory] = []

    @Published public private(set) var series: [VODItem] = []
    @Published public private(set) var seriesCategories: [MediaCategory] = []

    // MARK: - Sync & Progress States
    @Published public var isLoading: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var syncProgress: Double = 0.0
    @Published public var syncStage: String = ""
    @Published public var loadingMessage: String = ""
    @Published public var errorMessage: String? = nil

    @Published public var isAddAccountPresented: Bool = false
    @Published public var selectedTab: Int = 0

    private var storage = StorageManager.shared
    private var diskCache = DiskCacheService.shared

    private init() {
        loadFromCache()

        if storage.activeAccount != nil && channels.isEmpty && movies.isEmpty {
            Task {
                await syncActiveAccount()
            }
        }
    }

    // MARK: - Local Disk Cache Loading

    public func loadFromCache() {
        guard let account = storage.activeAccount else { return }
        if let cached = diskCache.loadMetadata(accountId: account.id) {
            self.channels = cached.channels
            self.liveCategories = cached.liveCategories
            self.movies = cached.movies
            self.vodCategories = cached.vodCategories
            self.series = cached.series
            self.seriesCategories = cached.seriesCategories
        }
    }

    // MARK: - Reset All Data

    public func resetAllData() {
        channels = []
        liveCategories = []
        movies = []
        vodCategories = []
        series = []
        seriesCategories = []
        isLoading = false
        isSyncing = false
        syncProgress = 0.0
        syncStage = ""
        loadingMessage = ""
        errorMessage = nil
        selectedTab = 0
        diskCache.clearAllCaches()
        storage.clearAll()
        PlaybackManager.shared.stop()
    }

    // MARK: - Sync Content with Real-time Progress

    public func syncActiveAccount() async {
        guard let account = storage.activeAccount else { return }

        isSyncing = true
        isLoading = true
        syncProgress = 0.05
        syncStage = "Sunucuya bağlanılıyor..."
        loadingMessage = syncStage
        errorMessage = nil

        switch account.type {
        case .xtream:
            await syncXtream(account: account)
        case .m3u:
            await syncM3U(account: account)
        }

        isLoading = false
        isSyncing = false
    }

    private func syncXtream(account: Account) async {
        do {
            // 1. Authenticate
            syncProgress = 0.15
            syncStage = "Hesap doğrulanıyor..."
            loadingMessage = syncStage

            let auth = try await XtreamCodesAPIService.shared.authenticate(
                serverUrl: account.serverUrl,
                username: account.username,
                password: account.password
            )

            var updatedAccount = account
            updatedAccount.isConnected = true
            updatedAccount.lastUpdated = Date()
            if let expStr = auth.userInfo?.expDate, let expTs = TimeInterval(expStr) {
                updatedAccount.expiryDate = Date(timeIntervalSince1970: expTs)
            }
            updatedAccount.maxConnections = auth.userInfo?.maxConnections
            updatedAccount.serverProtocol = auth.serverInfo?.serverProtocol
            storage.saveAccount(updatedAccount)

            let finalAccount = updatedAccount

            // 2. Fetch Live Categories & Channels
            syncProgress = 0.30
            syncStage = "Canlı TV kanalları indiriliyor..."
            loadingMessage = syncStage

            async let liveCatsTask = XtreamCodesAPIService.shared.getLiveCategories(account: finalAccount)
            async let liveChsTask = XtreamCodesAPIService.shared.getLiveStreams(account: finalAccount)
            let (lCats, lChs) = try await (liveCatsTask, liveChsTask)
            self.liveCategories = lCats
            self.channels = lChs

            // 3. Fetch Movies (VOD)
            syncProgress = 0.55
            syncStage = "Film kataloğu indiriliyor (\(lChs.count) kanal hazır)..."
            loadingMessage = syncStage

            async let vodCatsTask = XtreamCodesAPIService.shared.getVODCategories(account: finalAccount)
            async let vodStrsTask = XtreamCodesAPIService.shared.getVODStreams(account: finalAccount)
            let (vCats, vStrs) = try await (vodCatsTask, vodStrsTask)
            self.vodCategories = vCats
            self.movies = vStrs

            // 4. Fetch Series
            syncProgress = 0.80
            syncStage = "Diziler ve bölümler indiriliyor (\(vStrs.count) film hazır)..."
            loadingMessage = syncStage

            async let serCatsTask = XtreamCodesAPIService.shared.getSeriesCategories(account: finalAccount)
            async let serStrsTask = XtreamCodesAPIService.shared.getSeries(account: finalAccount)
            let (sCats, sStrs) = try await (serCatsTask, serStrsTask)
            self.seriesCategories = sCats
            self.series = sStrs

            // 5. Save everything to local disk cache
            syncProgress = 0.95
            syncStage = "Veriler cihaz hafızasına kaydediliyor..."
            loadingMessage = syncStage

            await diskCache.saveMetadata(
                accountId: finalAccount.id,
                channels: lChs,
                liveCategories: lCats,
                movies: vStrs,
                vodCategories: vCats,
                series: sStrs,
                seriesCategories: sCats
            )

            syncProgress = 1.0
            syncStage = "Tamamlandı!"

        } catch {
            self.errorMessage = friendlyErrorMessage(for: error)
        }
    }

    private func syncM3U(account: Account) async {
        let trimmedUrl = account.m3uUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedUrl) else {
            self.errorMessage = "Geçersiz M3U bağlantı adresi."
            return
        }

        // Smart auto-detection: If this M3U URL comes from an Xtream Codes server (e.g. get.php?username=...&password=...)
        if let creds = M3UParserService.shared.extractXtreamCredentials(from: trimmedUrl) {
            var upgraded = account
            upgraded.serverUrl = creds.serverUrl
            upgraded.username = creds.username
            upgraded.password = creds.password
            upgraded.type = .xtream
            storage.saveAccount(upgraded)
            await syncXtream(account: upgraded)
            return
        }

        do {
            syncProgress = 0.40
            syncStage = "M3U listesi indiriliyor ve işleniyor..."
            loadingMessage = syncStage

            let result = try await M3UParserService.shared.parse(url: url)

            self.liveCategories = result.categories
            self.channels = result.channels
            self.vodCategories = result.categories
            self.movies = result.movies
            self.seriesCategories = result.categories
            self.series = result.series

            syncProgress = 0.90
            syncStage = "Cihaz hafızasına kaydediliyor..."
            loadingMessage = syncStage

            await diskCache.saveMetadata(
                accountId: account.id,
                channels: result.channels,
                liveCategories: result.categories,
                movies: result.movies,
                vodCategories: result.categories,
                series: result.series,
                seriesCategories: result.categories
            )

            var updated = account
            updated.isConnected = true
            updated.lastUpdated = Date()
            storage.saveAccount(updated)

            syncProgress = 1.0
            syncStage = "Tamamlandı!"
        } catch {
            self.errorMessage = friendlyErrorMessage(for: error)
        }
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotFindHost:
                return "Girdiğiniz sunucu adresi (domain) bulunamadı. Lütfen bağlantı adresinizi (URL) kontrol edin."
            case NSURLErrorCannotConnectToHost:
                return "Sunucuya bağlanılamadı. Sunucu kapalı veya port adresi engellenmiş olabilir."
            case NSURLErrorTimedOut:
                return "Sunucu zaman aşımına uğradı. İnternet bağlantınızı kontrol edin."
            case NSURLErrorNotConnectedToInternet:
                return "İnternet bağlantısı bulunamadı."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
