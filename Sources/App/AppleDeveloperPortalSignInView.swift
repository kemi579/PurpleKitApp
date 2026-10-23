import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppStoreConnectSignInModel: ObservableObject {
    @Published var issuerID = ""
    @Published var keyID = ""
    @Published private(set) var hasPrivateKey = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var apps: [AppStoreConnectApp] = []
    private var privateKeyPEM = ""

    init() {
        if let data = try? KeychainVault.load(account: "app-store-connect-api-key"),
           let saved = try? JSONDecoder().decode(AppStoreConnectAPIKey.self, from: data) {
            issuerID = saved.issuerID
            keyID = saved.keyID
            privateKeyPEM = saved.privateKeyPEM
            hasPrivateKey = true
        }
    }

    var canConnect: Bool {
        !isBusy && !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasPrivateKey
    }

    func importPrivateKey(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8),
                  text.contains("-----BEGIN PRIVATE KEY-----"),
                  text.contains("-----END PRIVATE KEY-----") else {
                statusMessage = "Choose the original PEM .p8 API private key."
                return
            }
            let key = AppStoreConnectAPIKey(issuerID: issuerID, keyID: keyID, privateKeyPEM: text)
            _ = try AppStoreConnectAPI.makeTokenForValidation(key)
            privateKeyPEM = text
            hasPrivateKey = true
            statusMessage = "Private key loaded. Connect to verify the API credentials."
        } catch { statusMessage = error.localizedDescription }
    }

    func connect() async {
        guard canConnect else { return }
        isBusy = true
        defer { isBusy = false }
        let key = AppStoreConnectAPIKey(
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM
        )
        do {
            try KeychainVault.save(JSONEncoder().encode(key), account: "app-store-connect-api-key")
            apps = try await AppStoreConnectAPI.listApps(using: key)
            statusMessage = "Connected. Loaded \(apps.count) app(s) from App Store Connect."
        } catch { statusMessage = error.localizedDescription }
    }

    func disconnect() {
        do {
            try KeychainVault.delete(account: "app-store-connect-api-key")
            issuerID = ""; keyID = ""; privateKeyPEM = ""; hasPrivateKey = false
            apps = []; statusMessage = "Saved API credentials removed from this device."
        } catch { statusMessage = error.localizedDescription }
    }
}

struct AppleDeveloperPortalSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AppStoreConnectSignInModel()
    @State private var showingKeyImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Theme.primaryGradient)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                        Text("App Store Connect")
                            .font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                        Text("Use an official App Store Connect API key, not your Apple ID password. Create a Team API key in App Store Connect → Users and Access → Integrations. Enter its Issuer ID and Key ID, then select the downloaded .p8 file. The private key is stored in this device’s Keychain.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        VStack(spacing: 12) {
                            TextField("Issuer ID", text: $model.issuerID)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            TextField("Key ID", text: $model.keyID)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button {
                                showingKeyImporter = true
                            } label: {
                                Label(model.hasPrivateKey ? "Replace .p8 private key" : "Choose .p8 private key",
                                      systemImage: "key.horizontal").frame(maxWidth: .infinity).padding(10)
                            }.buttonStyle(.bordered)
                            Button {
                                Task { await model.connect() }
                            } label: {
                                HStack {
                                    if model.isBusy { ProgressView().tint(.white) }
                                    Text("Connect and load apps").fontWeight(.semibold)
                                }.frame(maxWidth: .infinity).padding(14)
                                    .background(Theme.primaryGradient).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.disabled(!model.canConnect)
                        }
                        if let status = model.statusMessage {
                            Text(status).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                        }
                        if !model.apps.isEmpty {
                            Text("Apps in this account").font(.headline).foregroundStyle(Theme.textPrimary)
                            ForEach(model.apps) { app in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.attributes.name).font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(app.attributes.bundleId).font(.caption.monospaced())
                                        .foregroundStyle(Theme.textSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(Theme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Button("Remove saved API credentials", role: .destructive) {
                            model.disconnect()
                        }.disabled(!model.hasPrivateKey)
                    }.padding(20)
                }
            }
            .navigationTitle("Developer API").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .fileImporter(isPresented: $showingKeyImporter, allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { model.importPrivateKey(from: url) }
                case .failure(let error): model.statusMessage = error.localizedDescription
                }
            }
        }
    }
}
