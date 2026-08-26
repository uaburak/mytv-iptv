import SwiftUI

public struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var storage = StorageManager.shared

    @State private var accountType: AccountType = .xtream
    @State private var name: String = ""
    @State private var serverUrl: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var m3uUrl: String = ""

    @State private var isConnecting = false
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Giriş Türü", selection: $accountType) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Liste Bilgileri") {
                    TextField("Liste / Profil Adı (Örn: Ev IPTV)", text: $name)
                }

                if accountType == .xtream {
                    Section("Xtream Codes Sunucu Bilgileri") {
                        TextField("Sunucu Adresi (Örn: https://sunucu.xyz:8443)", text: $serverUrl)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif

                        TextField("Kullanıcı Adı", text: $username)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif

                        SecureField("Şifre", text: $password)
                    }
                } else {
                    Section("M3U / M3U8 Bağlantısı") {
                        TextField("M3U / M3U8 URL (Örn: http://.../get.php?...)", text: $m3uUrl)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    }
                }

                // Real-time Download Progress when syncing
                if isConnecting {
                    Section("İndirme Durumu") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(appState.syncStage.isEmpty ? "Bağlanılıyor..." : appState.syncStage)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int(appState.syncProgress * 100))%")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tint)
                            }

                            ProgressView(value: appState.syncProgress, total: 1.0)
                                .tint(.accentColor)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button {
                        saveAndConnect()
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Veriler İndiriliyor...")
                            } else {
                                Text("Giriş Yap ve Listeyi İndir")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(isConnecting || !isFormValid)
                }
            }
            .navigationTitle("Yeni Liste Ekle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        dismiss()
                    }
                    .disabled(isConnecting)
                }
            }
        }
    }

    private var isFormValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return false }

        if accountType == .xtream {
            return !serverUrl.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !username.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !password.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !m3uUrl.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func saveAndConnect() {
        errorMessage = nil
        isConnecting = true

        Task {
            let newAccount = Account(
                name: name.trimmingCharacters(in: .whitespaces),
                type: accountType,
                serverUrl: serverUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password.trimmingCharacters(in: .whitespacesAndNewlines),
                m3uUrl: m3uUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            storage.saveAccount(newAccount)
            await appState.syncActiveAccount()

            isConnecting = false
            if appState.errorMessage == nil {
                dismiss()
            } else {
                errorMessage = appState.errorMessage
            }
        }
    }
}
