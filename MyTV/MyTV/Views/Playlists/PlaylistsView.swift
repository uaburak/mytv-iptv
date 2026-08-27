import SwiftUI

public struct PlaylistsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared

    @State private var selectedAccountForEdit: Account?
    @State private var isDeleteConfirmationPresented = false
    @State private var accountToDelete: Account?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // Header Banner / Bilgilendirme
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Çalma Listeleri")
                                .font(.headline)
                            Text("IPTV ve Xtream hesaplarınızı yönetin, düzenleyin veya yeni liste ekleyin.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Kayıtlı Listeler
                Section("Kayıtlı Listeler (\(storage.accounts.count))") {
                    if storage.accounts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Henüz eklenmiş bir liste bulunmuyor.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                appState.isAddAccountPresented = true
                            } label: {
                                Text("Yeni Liste Ekle")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(storage.accounts) { account in
                            let isActive = (storage.activeAccount?.id == account.id)

                            HStack(spacing: 12) {
                                // Status Indicator
                                Circle()
                                    .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(account.name)
                                            .font(.headline)
                                        if isActive {
                                            Text("AKTİF")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.2), in: Capsule())
                                                .foregroundStyle(.green)
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Text(account.type.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if let exp = account.expiryDate {
                                            Text("• Bitiş: \(exp.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isActive {
                                    storage.setActiveAccount(account)
                                    Task {
                                        await appState.syncActiveAccount()
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    accountToDelete = account
                                    isDeleteConfirmationPresented = true
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }

                                Button {
                                    Task {
                                        if !isActive {
                                            storage.setActiveAccount(account)
                                        }
                                        await appState.syncActiveAccount()
                                    }
                                } label: {
                                    Label("Yenile", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                // Yeni Ekle Butonu
                Section {
                    Button {
                        appState.isAddAccountPresented = true
                    } label: {
                        Label("Yeni Çalma Listesi Ekle", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.tint)
                    }
                }
            }
            .navigationTitle("Listeler")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.isAddAccountPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $appState.isAddAccountPresented) {
                AddAccountView()
            }
            .confirmationDialog(
                "Listeyi Sil",
                isPresented: $isDeleteConfirmationPresented,
                presenting: accountToDelete
            ) { acc in
                Button("Listeyi Sil", role: .destructive) {
                    storage.deleteAccount(id: acc.id)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { acc in
                Text("'\(acc.name)' adlı listeyi silmek istediğinizden emin misiniz?")
            }
        }
    }
}
