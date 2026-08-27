import SwiftUI

public struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared

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
                            Text(storage.activeAccount?.name ?? "Kullanıcı Profili")
                                .font(.title3.bold())

                            if let active = storage.activeAccount {
                                Text(active.username.isEmpty ? active.type.rawValue : active.username)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Giriş Yapılmadı")
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
                    Section("Abonelik ve Sunucu Durumu") {
                        LabeledContent {
                            Text(active.type.rawValue)
                                .fontWeight(.semibold)
                        } label: {
                            Label("Hesap Türü", systemImage: "badge.plus.radiowaves.right")
                        }

                        if active.type == .xtream && !active.serverUrl.isEmpty {
                            LabeledContent {
                                Text(active.serverUrl)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("Sunucu Adresi", systemImage: "server.rack")
                            }
                        }

                        if let exp = active.expiryDate {
                            let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
                            LabeledContent {
                                HStack(spacing: 6) {
                                    Text(exp.formatted(date: .abbreviated, time: .omitted))
                                    if daysLeft > 0 {
                                        Text("(\(daysLeft) gün)")
                                            .font(.caption.bold())
                                            .foregroundStyle(daysLeft < 7 ? .red : .green)
                                    }
                                }
                            } label: {
                                Label("Bitiş Tarihi", systemImage: "calendar.badge.clock")
                            }
                        }

                        if let last = active.lastUpdated {
                            LabeledContent {
                                Text(last.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("Son Senkronizasyon", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }

                // 3. İstatistikler
                Section("İçerik İstatistikleri") {
                    LabeledContent {
                        Text("\(storage.favorites.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label("Favori İçerikler", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }

                    LabeledContent {
                        Text("\(appState.channels.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label("Canlı Kanallar", systemImage: "tv.fill")
                            .foregroundStyle(.blue)
                    }

                    LabeledContent {
                        Text("\(appState.movies.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label("Filmler", systemImage: "film.fill")
                            .foregroundStyle(.purple)
                    }

                    LabeledContent {
                        Text("\(appState.series.count)")
                            .font(.subheadline.bold())
                    } label: {
                        Label("Diziler", systemImage: "play.tv.fill")
                            .foregroundStyle(.orange)
                    }
                }

                // 4. Ayarlara Geçiş
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Uygulama Ayarları", systemImage: "gearshape.fill")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Profil")
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
