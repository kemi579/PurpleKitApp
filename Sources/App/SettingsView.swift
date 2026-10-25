import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var certs: CertificateStore
    @ObservedObject private var signer = IPASigningService.shared
    @ObservedObject private var installer = DeviceInstaller.shared
    @State private var showSignIn = false
    @State private var showLogout = false
    @State private var showLibrary = false
    @State private var showPairingImporter = false
    @State private var pairingError: String?

    var body: some View {
        NavigationStack {
            ToolLayout {
                SectionHeading(title: "Приложения")
                SettingsGroup {
                    Button { showLibrary = true } label: {
                        SettingsRow(title: "Библиотека IPA", icon: "square.stack.3d.up")
                    }
                    .buttonStyle(.plain)
                }

                SectionHeading(title: "Подписание")
                SettingsGroup {
                    Button { showSignIn = true } label: {
                        SettingsRow(title: "Apple ID", value: certs.appleID.isEmpty ? "Не подключён" : certs.appleID,
                                    icon: "person.crop.circle")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider(leading: 56)
                    SettingsRow(title: "Сертификат", value: certs.certName.isEmpty ? "Не выдан" : certs.certName,
                                showsChevron: false)
                    if let expiry = certs.certExpires {
                        SettingsDivider()
                        SettingsRow(title: "Срок действия", value: expiry.formatted(date: .abbreviated, time: .omitted),
                                    showsChevron: false)
                    }
                    StatusBadges {
                        PillBadge(text: certs.isCertHealthy ? "Valid" : certs.certStatusText,
                                  color: certs.isCertHealthy ? Theme.success : Theme.error)
                        if let days = certs.daysLeft {
                            PillBadge(text: "\(days) дней", color: days <= 2 ? Theme.error : Theme.secondaryText)
                        }
                    }
                }
                if certs.isLoggedIn {
                    Button("Отключить Apple ID", role: .destructive) { showLogout = true }
                        .frame(minHeight: 44)
                }

                SectionHeading(title: "Подключение")
                SettingsGroup {
                    Button { showPairingImporter = true } label: {
                        SettingsRow(title: "Pairing-файл", value: installer.hasPairingFile ? "Импортирован" : "Добавить",
                                    icon: "link")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider(leading: 56)
                    NavigationLink { AnisetteServerSettingsView() } label: {
                        SettingsRow(title: "Серверы Anisette", icon: "server.rack")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    InputField(placeholder: "UDID устройства", text: $signer.deviceUDID)
                }
                Text("Pairing-файл нужно один раз получить на компьютере. Для установки включи совместимый локальный VPN.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if let pairingError {
                    Text(pairingError).font(.subheadline).foregroundStyle(Theme.error)
                }

                SectionHeading(title: "О приложении")
                SettingsGroup {
                    SettingsRow(title: "Версия", value: "1.0.0", showsChevron: false)
                    SettingsDivider()
                    SettingsRow(title: "Bundle ID", value: "com.kemi579.PurpleKit", showsChevron: false)
                    SettingsDivider()
                    SettingsRow(title: "Минимальная iOS", value: "16.0", showsChevron: false)
                    SettingsDivider()
                    SettingsRow(title: "Оформление", value: "Тёмное", showsChevron: false)
                }
                Text("Подпись: SideSign. Установка: Minimuxer. Сведения о лицензиях доступны в репозитории.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if installer.hasPairingFile {
                        Menu {
                            Button(role: .destructive) { try? installer.clearPairingFile() } label: {
                                Label("Удалить pairing-файл", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Действия с подключением")
                    }
                }
            }
            .sheet(isPresented: $showLibrary) {
                LibraryView(onOpenSettings: { showLibrary = false })
            }
            .sheet(isPresented: $showSignIn) { AppleDeveloperPortalSignInView() }
            .fileImporter(isPresented: $showPairingImporter, allowedContentTypes: [.data, .item],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try installer.importPairingFile(from: url)
                        pairingError = nil
                    } catch { pairingError = error.localizedDescription }
                case .failure(let error): pairingError = error.localizedDescription
                }
            }
            .confirmationDialog("Отключить Apple ID?", isPresented: $showLogout, titleVisibility: .visible) {
                Button("Отключить", role: .destructive) {
                    certs.logout()
                    try? KeychainVault.delete(account: "sidesign-auth-session")
                    try? KeychainVault.delete(account: "sidesign-development-certificate-p12")
                    try? KeychainVault.delete(account: "sidesign-development-certificate-password")
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
}
