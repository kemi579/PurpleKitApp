import SwiftUI

struct AnisetteServerSettingsView: View {
    @ObservedObject private var catalog = AnisetteServerCatalog.shared
    @FocusState private var sourceFocused: Bool

    var body: some View {
        ToolLayout(primaryTitle: catalog.isLoading ? "Загрузка…" : "Обновить каталог",
                   isBusy: catalog.isLoading,
                   primaryAction: {
                       sourceFocused = false
                       Task { await catalog.refresh() }
                   }) {
            SectionHeading(title: "Источник")
            SettingsGroup {
                InputField(placeholder: "HTTPS URL каталога", text: $catalog.sourceURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($sourceFocused)
            }
            if let error = catalog.lastError {
                Text(error).font(.subheadline).foregroundStyle(Theme.error)
            }

            SectionHeading(title: "Серверы")
            if catalog.servers.isEmpty {
                EmptyStateView(title: "Каталог пуст", message: "Загрузи каталог SideStore или укажи свой HTTPS URL.")
            } else {
                SettingsGroup {
                    ForEach(catalog.servers) { server in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(server.name).font(.body)
                            Text(server.address).font(.footnote).foregroundStyle(Theme.secondaryText)
                                .textSelection(.enabled)
                            if let health = catalog.serverHealth[server.id] { healthLabel(health) }
                            if catalog.checkingServerIDs.contains(server.id) {
                                ProgressView("Проверка…")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.rowInset)
                        .contextMenu {
                            Button {
                                Task { await catalog.checkServer(server) }
                            } label: { Label("Проверить сервер", systemImage: "network") }
                            .disabled(catalog.checkingServerIDs.contains(server.id))
                        }
                        .accessibilityAction(named: "Проверить сервер") {
                            Task { await catalog.checkServer(server) }
                        }
                        if server.id != catalog.servers.last?.id { SettingsDivider() }
                    }
                }
            }
            Text("Успешная проверка подтверждает доступность сервера, но не его надёжность и не авторизацию Apple.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .navigationTitle("Anisette")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func healthLabel(_ health: AnisetteServerCatalog.ServerHealth) -> some View {
        switch health {
        case .online: PillBadge(text: "HTTP 200", color: Theme.success)
        case .httpError(let code): PillBadge(text: "HTTP \(code)", color: Theme.error)
        case .invalidResponse: PillBadge(text: "Некорректный ответ", color: Theme.error)
        case .unavailable: PillBadge(text: "Недоступен", color: Theme.error)
        }
    }
}
