import Foundation
import SwiftUI
import SideSign

/// Real Apple Developer Portal authentication backed by SideSign.
/// Passwords are held only for the duration of an explicit sign-in attempt.
@MainActor
final class SideSignAppleAccountProvider: ObservableObject {
    @Published var appleID = ""
    @Published var password = ""
    /// Selected Anisette server address (HTTPS URL from catalog).
    @Published var selectedServerAddress = ""
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Not signed in"
    @Published private(set) var account: Account?
    @Published private(set) var teams: [Team] = []
    @Published var selectedTeamID = ""
    @Published private(set) var hasCertificate = false
    @Published private(set) var certificateName = ""
    @Published private(set) var certificateExpires: Date?
    @Published var verificationPrompt: String?
    @Published var verificationCode = ""
    @Published var selectedDelivery: TwoFactorDeliveryMode = .trustedDevice
    @Published private(set) var availablePhones: [TrustedPhoneNumber] = []

    private var pendingVerification: CheckedContinuation<TwoFactorResponse, Never>?
    private var authSession: AuthSession?
    private let anisette = AnisetteDataManager.shared
    private let portal = DeveloperPortal.shared

    private static let selectedServerKey = "PurpleKit.selectedAnisetteServer"

    init() {
        appleID = (try? KeychainVault.load(account: "apple-id-email")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        selectedServerAddress = UserDefaults.standard.string(forKey: Self.selectedServerKey) ?? ""

        // Restore certificate metadata if present in Keychain
        if (try? KeychainVault.load(account: "sidesign-development-certificate-p12")) != nil {
            hasCertificate = true
            certificateName = UserDefaults.standard.string(forKey: "PurpleKit.certName") ?? "Development certificate"
            let exp = UserDefaults.standard.double(forKey: "PurpleKit.certExpires")
            if exp > 0 { certificateExpires = Date(timeIntervalSince1970: exp) }
        }

        if let data = try? KeychainVault.load(account: "sidesign-auth-session"),
           let session = try? JSONDecoder().decode(AuthSession.self, from: data),
           session.session.isValid {
            authSession = session
            account = session.account
            status = "Session restored for \(session.account.appleID)."
            CertificateStore.shared.applyAuthenticatedSession(
                email: session.account.appleID,
                team: nil
            )
            if hasCertificate {
                CertificateStore.shared.applyCertificate(name: certificateName, expires: certificateExpires)
            }
            Task { await loadTeams() }
        }
    }

    var canSignIn: Bool {
        !isBusy &&
        !appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        validAnisetteURL != nil
    }

    private var validAnisetteURL: URL? {
        guard let url = URL(string: selectedServerAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else { return nil }
        return url
    }

    func signIn() async {
        guard canSignIn, let serverURL = validAnisetteURL else {
            status = "Enter Apple ID, password, and pick an Anisette server."
            return
        }
        isBusy = true
        status = "Fetching Anisette data…"
        defer {
            isBusy = false
            password = ""
        }
        UserDefaults.standard.set(serverURL.absoluteString, forKey: Self.selectedServerKey)
        do {
            let (anisetteData, _) = try await anisette.fetchAnisetteData(
                mode: .remote(server: serverURL),
                identifier: UUID()
            )
            status = "Signing in with Apple…"
            let credentialsPassword = password
            let result = try await portal.authenticate(
                appleID: appleID,
                password: credentialsPassword,
                anisetteData: anisetteData,
                xcodeVersion: "16.0",
                verificationHandler: { [weak self] request in
                    guard let self else { return .cancel }
                    return await self.handleVerification(request)
                }
            )
            authSession = result
            account = result.account
            try KeychainVault.save(Data(appleID.trimmingCharacters(in: .whitespacesAndNewlines).utf8), account: "apple-id-email")
            try KeychainVault.save(try JSONEncoder().encode(result), account: "sidesign-auth-session")
            CertificateStore.shared.applyAuthenticatedSession(
                email: result.account.appleID,
                team: nil
            )
            status = "Signed in. Loading teams…"
            await loadTeams()
        } catch {
            status = Self.safeError(error)
            authSession = nil
            account = nil
            teams = []
            try? KeychainVault.delete(account: "sidesign-auth-session")
            CertificateStore.shared.logout()
        }
    }

    private func handleVerification(_ request: TwoFactorRequest) async -> TwoFactorResponse {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.pendingVerification = continuation
                self.verificationCode = ""
                switch request {
                case .selectDeliveryMethod(let preferred, let phones):
                    self.availablePhones = phones
                    self.selectedDelivery = preferred
                    self.verificationPrompt = "Choose how Apple should send your verification code."
                case .trustedDevice(let error):
                    self.selectedDelivery = .trustedDevice
                    self.availablePhones = []
                    self.verificationPrompt = error ?? "Approve the sign-in on a trusted Apple device, then continue."
                case .sms(let phones, _, let error):
                    self.availablePhones = phones
                    self.selectedDelivery = .sms
                    self.verificationPrompt = error ?? "Enter the code sent by SMS."
                case .voice(let phones, _, let error):
                    self.availablePhones = phones
                    self.selectedDelivery = .voice
                    self.verificationPrompt = error ?? "Enter the code from the Apple verification call."
                }
            }
        }
    }

    func submitVerification() {
        guard let continuation = pendingVerification else { return }
        pendingVerification = nil
        verificationPrompt = nil
        switch selectedDelivery {
        case .trustedDevice:
            continuation.resume(returning: verificationCode.isEmpty ? .requestTrustedDevice : .verificationCode(verificationCode))
        case .sms:
            if !verificationCode.isEmpty {
                continuation.resume(returning: .verificationCode(verificationCode))
            } else if let phone = availablePhones.first {
                continuation.resume(returning: .requestSMS(phoneID: phone.id))
            } else {
                continuation.resume(returning: .cancel)
            }
        case .voice:
            if !verificationCode.isEmpty {
                continuation.resume(returning: .verificationCode(verificationCode))
            } else if let phone = availablePhones.first {
                continuation.resume(returning: .requestVoice(phoneID: phone.id))
            } else {
                continuation.resume(returning: .cancel)
            }
        }
    }

    func cancelVerification() {
        let continuation = pendingVerification
        pendingVerification = nil
        verificationPrompt = nil
        continuation?.resume(returning: .cancel)
    }

    func loadTeams() async {
        guard let authSession else { return }
        do {
            teams = try await portal.fetchTeams(for: authSession.account, session: authSession.session)
            if selectedTeamID.isEmpty { selectedTeamID = teams.first?.identifier ?? "" }
            let teamLabel = teams.first(where: { $0.identifier == selectedTeamID })?.name
            CertificateStore.shared.applyAuthenticatedSession(
                email: authSession.account.appleID,
                team: teamLabel
            )
            status = "Signed in as \(authSession.account.appleID). \(teams.count) team(s)."
        } catch {
            status = "Signed in, but team loading failed: \(Self.safeError(error))"
        }
    }

    func createDevelopmentCertificate() async {
        guard let authSession,
              let team = teams.first(where: { $0.identifier == selectedTeamID }) else {
            status = "Sign in and select a team first."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let keyStore = try await portal.addCertificate(
                machineName: "PurpleKit",
                type: .iosDevelopment,
                to: team,
                session: authSession.session
            )
            let p12Password = UUID().uuidString
            let p12 = try keyStore.exportP12(password: p12Password)
            try KeychainVault.save(p12, account: "sidesign-development-certificate-p12")
            try KeychainVault.save(Data(p12Password.utf8), account: "sidesign-development-certificate-password")
            certificateName = keyStore.certificate.name
            certificateExpires = keyStore.certificate.expiryDate
            hasCertificate = true
            CertificateStore.shared.applyCertificate(name: certificateName, expires: certificateExpires)
            CertificateStore.shared.applyAuthenticatedSession(
                email: authSession.account.appleID,
                team: team.name
            )
            status = "Development certificate issued and saved to Keychain."
        } catch {
            status = "Certificate request failed: \(Self.safeError(error))"
        }
    }

    func signOut() {
        cancelVerification()
        authSession = nil
        account = nil
        teams = []
        hasCertificate = false
        certificateName = ""
        certificateExpires = nil
        try? KeychainVault.delete(account: "sidesign-auth-session")
        try? KeychainVault.delete(account: "sidesign-development-certificate-p12")
        try? KeychainVault.delete(account: "sidesign-development-certificate-password")
        CertificateStore.shared.logout()
        status = "Signed out. Session and certificate removed."
    }

    private static func safeError(_ error: Error) -> String {
        if let error = error as? LocalizedError, let message = error.errorDescription {
            return String(message.prefix(400))
        }
        return "Authentication failed. Check network, Anisette server, and Apple account."
    }
}

// MARK: - Sign-in screen

struct AppleDeveloperPortalSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SideSignAppleAccountProvider()
    @StateObject private var catalog = AnisetteServerCatalog.shared
    @State private var showServerList = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                Circle()
                    .fill(Theme.primary.opacity(0.2))
                    .frame(width: 260, height: 260)
                    .blur(radius: 80)
                    .offset(x: -70, y: -140)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Hero
                        VStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(Theme.primaryGradient)
                            Text("Apple ID")
                                .font(.title2.bold())
                                .foregroundStyle(Theme.textPrimary)
                            Text("Sign in · 2FA · development certificate")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                        // Credentials card
                        VStack(alignment: .leading, spacing: 14) {
                            fieldLabel("Apple ID")
                            TextField("email@icloud.com", text: $model.appleID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .padding(14)
                                .background(fieldBg)
                                .foregroundColor(Theme.textPrimary)

                            fieldLabel("Password")
                            SecureField("Apple ID password", text: $model.password)
                                .padding(14)
                                .background(fieldBg)
                                .foregroundColor(Theme.textPrimary)

                            // Anisette server — expandable picker
                            fieldLabel("Anisette server")
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showServerList.toggle()
                                }
                                if catalog.servers.isEmpty {
                                    Task { await catalog.refresh() }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(selectedServerName)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(Theme.textPrimary)
                                            .lineLimit(1)
                                        if !model.selectedServerAddress.isEmpty {
                                            Text(model.selectedServerAddress)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(Theme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: showServerList ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.primaryLight)
                                }
                                .padding(14)
                                .background(fieldBg)
                            }
                            .buttonStyle(.plain)

                            if showServerList {
                                VStack(spacing: 0) {
                                    if catalog.isLoading {
                                        HStack {
                                            ProgressView().controlSize(.small)
                                            Text("Loading servers…")
                                                .font(.caption)
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                        .padding(14)
                                    } else if catalog.servers.isEmpty {
                                        Text(catalog.lastError ?? "No servers. Pull to refresh.")
                                            .font(.caption)
                                            .foregroundColor(Theme.warning)
                                            .padding(14)
                                    } else {
                                        ForEach(catalog.servers) { server in
                                            Button {
                                                model.selectedServerAddress = server.address
                                                withAnimation { showServerList = false }
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(server.name)
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .foregroundColor(Theme.textPrimary)
                                                        Text(server.address)
                                                            .font(.system(size: 11, design: .monospaced))
                                                            .foregroundColor(Theme.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                    if model.selectedServerAddress == server.address {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundColor(Theme.primaryLight)
                                                    }
                                                }
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 12)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            if server.id != catalog.servers.last?.id {
                                                Divider().overlay(Color.white.opacity(0.08))
                                            }
                                        }
                                    }

                                    Divider().overlay(Color.white.opacity(0.1))

                                    Button {
                                        Task { await catalog.refresh() }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Refresh list")
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(Theme.primaryLight)
                                        .frame(maxWidth: .infinity)
                                        .padding(12)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(catalog.isLoading)
                                }
                                .background {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(Theme.glassStroke, lineWidth: 1)
                                        }
                                }
                            }

                            // Sign in button
                            Button {
                                Task { await model.signIn() }
                            } label: {
                                HStack(spacing: 8) {
                                    if model.isBusy {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "apple.logo")
                                    }
                                    Text(model.isBusy ? "Connecting…" : "Sign in")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .foregroundColor(.white)
                                .background(Theme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Theme.primary.opacity(0.4), radius: 10, x: 0, y: 5)
                            }
                            .buttonStyle(.plain)
                            .disabled(!model.canSignIn)
                            .opacity(model.canSignIn ? 1 : 0.55)
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 20)

                        // Teams + cert (after sign-in)
                        if !model.teams.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Developer team")
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)

                                Picker("Team", selection: $model.selectedTeamID) {
                                    ForEach(model.teams, id: \.identifier) { team in
                                        Text("\(team.name) (\(team.type.displayName))")
                                            .tag(team.identifier)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Theme.primaryLight)
                                .padding(12)
                                .background(fieldBg)

                                Button {
                                    Task { await model.createDevelopmentCertificate() }
                                } label: {
                                    HStack {
                                        if model.isBusy {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "checkmark.seal.fill")
                                        }
                                        Text(model.hasCertificate
                                              ? "Request another certificate"
                                              : "Request development certificate")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundColor(.white)
                                    .background(Theme.neonGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isBusy)

                                if model.hasCertificate {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label("Certificate in Keychain", systemImage: "lock.shield.fill")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(Theme.success)
                                        Text(model.certificateName)
                                            .font(.caption.monospaced())
                                            .foregroundColor(Theme.textPrimary)
                                        if let expiry = model.certificateExpires {
                                            Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Theme.success.opacity(0.1))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(Theme.success.opacity(0.25), lineWidth: 1)
                                            }
                                    }
                                }
                            }
                            .padding(16)
                            .glassCard(cornerRadius: 18)
                        }

                        // Status
                        Text(model.status)
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 4)

                        if model.account != nil {
                            Button(role: .destructive) {
                                model.signOut()
                            } label: {
                                Text("Sign out and remove session")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.error)
                        }

                        Text("Password is never saved. Anisette only supplies device metadata — login goes to Apple. Free Apple ID certificates last ~7 days.")
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                            .padding(.bottom, 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.primaryLight)
                }
            }
            .task {
                if catalog.servers.isEmpty {
                    await catalog.refresh()
                }
                // Auto-select first server if none chosen
                if model.selectedServerAddress.isEmpty,
                   let first = catalog.servers.first {
                    model.selectedServerAddress = first.address
                }
            }
            .alert(
                model.verificationPrompt ?? "Apple verification",
                isPresented: Binding(
                    get: { model.verificationPrompt != nil },
                    set: { if !$0 { model.cancelVerification() } }
                )
            ) {
                TextField("Verification code", text: $model.verificationCode)
                    .keyboardType(.numberPad)
                Button("Continue") { model.submitVerification() }
                Button("Cancel", role: .cancel) { model.cancelVerification() }
            } message: {
                Text("For SMS/voice enter the code. For trusted device, approve on your device then continue.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedServerName: String {
        if let match = catalog.servers.first(where: { $0.address == model.selectedServerAddress }) {
            return match.name
        }
        if model.selectedServerAddress.isEmpty {
            return "Select a server"
        }
        return "Custom server"
    }

    private var fieldBg: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.7)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.glassStroke, lineWidth: 1)
            }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.textSecondary)
    }
}
