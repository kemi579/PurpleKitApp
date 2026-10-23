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
                        Text("Load a server list from a SideStore-compatible JSON catalog. The default is SideStore's public community catalog; you can also use your own HTTPS URL.")
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
                            EmptyStateView(icon: "server.rack", title: "No catalog loaded", message: "Load the default SideStore catalog or enter another trusted HTTPS catalog URL.")
                                .padding(.vertical, 8)
                        } else {
                            ForEach(catalog.servers) { server in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(server.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                    Text(server.address)
                                        .font(.caption.monospaced())
                                        .foregroundColor(Theme.textSecondary)
                                        .textSelection(.enabled)
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
                    Label("Security: only HTTPS catalog and server URLs are accepted. Catalog entries are not proof that a server is online or trustworthy. This screen configures the list only; Apple ID authentication, signing and installation are not implemented yet.", systemImage: "info.circle")
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
}
