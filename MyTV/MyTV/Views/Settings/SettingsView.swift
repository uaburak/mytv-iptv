import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared

    @State private var isResetAlertPresented = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Kayıtlı Çalma Listeleri") {
                    if storage.accounts.isEmpty {
                        Text("Kayıtlı bir çalma listesi bulunmuyor.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(storage.accounts) { account in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name)
                                        .font(.headline)
                                    Text(account.type.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if storage.activeAccount?.id == account.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                storage.setActiveAccount(account)
                                Task {
                                    await appState.syncActiveAccount()
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                storage.deleteAccount(id: storage.accounts[idx].id)
                            }
                        }
                    }

                    Button {
                        appState.isAddAccountPresented = true
                    } label: {
                        Label("Yeni Liste Ekle", systemImage: "plus")
                    }
                }

                if let active = storage.activeAccount {
                    Section("Aktif Liste Detayları") {
                        LabeledContent("Profil Adı", value: active.name)
                        LabeledContent("Format", value: active.type.rawValue)
                        if active.type == .xtream {
                            LabeledContent("Sunucu", value: active.serverUrl)
                            LabeledContent("Kullanıcı", value: active.username)
                        }
                        if let exp = active.expiryDate {
                            LabeledContent("Bitiş Tarihi", value: exp.formatted(date: .abbreviated, time: .omitted))
                        }
                        if let last = active.lastUpdated {
                            LabeledContent("Son Senkronizasyon", value: last.formatted(date: .abbreviated, time: .shortened))
                        }

                        Button {
                            Task {
                                await appState.syncActiveAccount()
                            }
                        } label: {
                            Label("Listeyi Yenile / Güncelle", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Section("Veri ve Bellek Yönetimi") {
                    Button(role: .destructive) {
                        isResetAlertPresented = true
                    } label: {
                        HStack {
                            Label("Tüm Verileri Sıfırla", systemImage: "trash.fill")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }

                Section("Uygulama Bilgisi") {
                    LabeledContent("Uygulama Adı", value: "MyTV")
                    LabeledContent("Sürüm", value: "1.0")
                }
            }
            .navigationTitle("Ayarlar")
            .sheet(isPresented: $appState.isAddAccountPresented) {
                AddAccountView()
            }
            .alert("Tüm Veriler Sıfırlansın mı?", isPresented: $isResetAlertPresented) {
                Button("Sıfırla", role: .destructive) {
                    appState.resetAllData()
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Kayıtlı tüm çalma listeleri, kanallar, filmler ve diziler temizlenecektir. Bu işlem geri alınamaz.")
            }
        }
    }
}
