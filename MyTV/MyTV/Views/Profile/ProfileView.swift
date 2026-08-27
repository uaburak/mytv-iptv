import SwiftUI

public struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // 1. Kullanıcı / Profil Kartı
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)

                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(storage.activeAccount?.name ?? (appLanguage == "tr" ? "Kullanıcı Profili" : "User Profile"))
                                .font(.title3.bold())

                            if let active = storage.activeAccount {
                                Text(active.username.isEmpty ? active.type.rawValue : active.username)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(appLanguage == "tr" ? "Giriş Yapılmadı" : "No Active Account")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                // 2. Aktif Hesap ve Abonelik Durumu
                if let active = storage.activeAccount {
                    Section(appLanguage == "tr" ? "Abonelik ve Sunucu Durumu" : "Subscription & Server Status") {
                        LabeledContent {
                            Text(active.type.rawValue)
                                .fontWeight(.semibold)
                        } label: {
                            Label(appLanguage == "tr" ? "Hesap Türü" : "Account Type", systemImage: "badge.plus.radiowaves.right")
                        }

                        if active.type == .xtream && !active.serverUrl.isEmpty {
                            LabeledContent {
                                Text(active.serverUrl)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label(appLanguage == "tr" ? "Sunucu Adresi" : "Server Address", systemImage: "server.rack")
                            }
                        }

                        if let exp = active.expiryDate {
                            let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
                            LabeledContent {
                                HStack(spacing: 6) {
                                    Text(exp.formatted(date: .abbreviated, time: .omitted))
                                    if daysLeft > 0 {
                                        Text(appLanguage == "tr" ? "(\(daysLeft) gün)" : "(\(daysLeft) days)")
                                            .font(.caption.bold())
                                            .foregroundStyle(daysLeft < 7 ? .red : .green)
                                    }
                                }
                            } label: {
                                Label(appLanguage == "tr" ? "Bitiş Tarihi" : "Expiry Date", systemImage: "calendar.badge.clock")
                            }
                        }

                        if let last = active.lastUpdated {
                            LabeledContent {
                                Text(last.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label(appLanguage == "tr" ? "Son Senkronizasyon" : "Last Sync", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }

                // 3. İstatistikler
                Section(appLanguage == "tr" ? "İçerik İstatistikleri" : "Content Statistics") {
                    LabeledContent {
                        Text("\(storage.favorites.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label(appLanguage == "tr" ? "Favori İçerikler" : "Favorites", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }

                    LabeledContent {
                        Text("\(appState.channels.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label(appLanguage == "tr" ? "Canlı Kanallar" : "Live Channels", systemImage: "tv.fill")
                            .foregroundStyle(.blue)
                    }

                    LabeledContent {
                        Text("\(appState.movies.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label(appLanguage == "tr" ? "Filmler" : "Movies", systemImage: "film.fill")
                            .foregroundStyle(.purple)
                    }

                    LabeledContent {
                        Text("\(appState.series.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label(appLanguage == "tr" ? "Diziler" : "Series", systemImage: "play.tv.fill")
                            .foregroundStyle(.orange)
                    }
                }

                // 4. Dil / Language
                Section(appLanguage == "tr" ? "Dil ve Tercihler" : "Language & Preferences") {
                    Picker(selection: $appLanguage) {
                        Text("English").tag("en")
                        Text("Türkçe").tag("tr")
                    } label: {
                        Label(appLanguage == "tr" ? "Uygulama Dili" : "App Language", systemImage: "globe")
                    }
                    .pickerStyle(.menu)
                }

                // 5. Ayarlara Geçiş
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(appLanguage == "tr" ? "Uygulama Ayarları" : "App Settings", systemImage: "gearshape.fill")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle(appLanguage == "tr" ? "Profil" : "Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}
