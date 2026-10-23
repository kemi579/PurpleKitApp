import SwiftUI

struct AnisetteServerSettingsView: View {
    @StateObject private var catalog = AnisetteServerCatalog.shared
    @FocusState private var sourceFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anisette servers")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.primaryGradient)
                        Text("Load a server list from SideStore's public community catalog, or use your own HTTPS URL.")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Catalog URL")
                            .font(.headline)
                            .foregroundColor(Theme.textPrimary)
                        TextField("https://servers.sidestore.io/servers.json", text: $catalog.sourceURL, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($sourceFocused)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(12)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        PurpleButton(title: catalog.isLoading ? "Loading catalog…" : "Load / refresh catalog", icon: "arrow.clockwise") {
                            sourceFocused = false
                            Task { await catalog.refresh() }
                        }
                        .disabled(catalog.isLoading)
                        if let error = catalog.lastError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(Theme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .background(Theme.cardGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Catalog entries")
                                .font(.headline)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text("\(catalog.servers.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(Theme.textSecondary)
                        }

                        if catalog.servers.isEmpty {
                            EmptyStateView(
                                icon: "server.rack",
                                title: "No catalog loaded",
                                message: "Load the SideStore catalog or enter another trusted HTTPS catalog URL."
                            )
                            .padding(.vertical, 8)
                        } else {
                            ForEach(catalog.servers) { server in
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(server.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(Theme.textPrimary)
                                        Text(server.address)
                                            .font(.caption.monospaced())
                                            .foregroundColor(Theme.textSecondary)
                                            .textSelection(.enabled)
                                    }

                                    HStack(spacing: 10) {
                                        Button {
                                            Task { await catalog.checkServer(server) }
                                        } label: {
                                            HStack(spacing: 6) {
                                                if catalog.checkingServerIDs.contains(server.id) {
                                                    ProgressView().controlSize(.small)
                                                } else {
                                                    Image(systemName: "network")
                                                }
                                                Text(catalog.checkingServerIDs.contains(server.id) ? "Testing…" : "Test server")
                                            }
                                            .font(.caption.weight(.semibold))
                                        }
                                        .disabled(catalog.checkingServerIDs.contains(server.id))

                                        if let health = catalog.serverHealth[server.id] {
                                            healthLabel(health)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                if server.id != catalog.servers.last?.id {
                                    Divider().overlay(Color.white.opacity(0.08))
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Label("A successful test only confirms that HTTPS /v3/client_info responded with HTTP 200 at that moment. It does not verify server trust or complete Apple authentication. Never send your Apple ID password to an Anisette server.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Anisette")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
            }
        }
    }

    @ViewBuilder
    private func healthLabel(_ health: AnisetteServerCatalog.ServerHealth) -> some View {
        switch health {
        case .online:
            Label("HTTP 200", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(Theme.success)
        case .httpError(let code):
            Label("HTTP \(code)", systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(Theme.warning)
        case .invalidResponse:
            Label("Invalid response", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(Theme.warning)
        case .unavailable:
            Label("Unavailable", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundColor(Theme.warning)
        }
    }
}
