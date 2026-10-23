import Foundation
import SwiftUI
import SideSign

/// Multi-step 2FA UI state driven by SideSign verification callbacks.
enum TwoFactorPhase: Equatable {
    case none
    /// Pick trusted device / SMS / voice and request the code.
    case chooseMethod
    /// Waiting after user tapped "Send / Approve".
    case waitingForDelivery
    /// Enter the 6-digit code (sheet re-presented after request).
    case enterCode
}

/// Real Apple Developer Portal authentication backed by SideSign.
/// Passwords are held only for the duration of an explicit sign-in attempt.
@MainActor
final class SideSignAppleAccountProvider: ObservableObject {
    @Published var appleID = ""
    @Published var password = ""
    @Published var selectedServerAddress = ""
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Not signed in"
    @Published private(set) var account: Account?
    @Published private(set) var teams: [Team] = []
    @Published var selectedTeamID = ""
    @Published private(set) var hasCertificate = false
    @Published private(set) var certificateName = ""
    @Published private(set) var certificateExpires: Date?

    // 2FA
    @Published var twoFactorPhase: TwoFactorPhase = .none
    @Published var twoFactorTitle = ""
    @Published var twoFactorMessage = ""
    @Published var verificationCode = ""
    @Published var selectedDelivery: TwoFactorDeliveryMode = .trustedDevice
    @Published private(set) var availablePhones: [TrustedPhoneNumber] = []
    @Published var selectedPhoneID = ""

    private var pendingVerification: CheckedContinuation<TwoFactorResponse, Never>?
    private var authSession: AuthSession?
    private let anisette = AnisetteDataManager.shared
    private let portal = DeveloperPortal.shared

    private static let selectedServerKey = "PurpleKit.selectedAnisetteServer"

    init() {
        appleID = (try? KeychainVault.load(account: "apple-id-email")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        selectedServerAddress = UserDefaults.standard.string(forKey: Self.selectedServerKey) ?? ""

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

    var showTwoFactorSheet: Bool {
        twoFactorPhase != .none
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

    // MARK: - 2FA multi-step

    private func handleVerification(_ request: TwoFactorRequest) async -> TwoFactorResponse {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.pendingVerification = continuation
                self.verificationCode = ""

                switch request {
                case .selectDeliveryMethod(let preferred, let phones):
                    self.availablePhones = phones
                    self.selectedDelivery = preferred
                    self.selectedPhoneID = phones.first?.id ?? ""
                    self.twoFactorTitle = "Verification method"
                    self.twoFactorMessage = "Choose how Apple should send the code, then tap Continue."
                    self.twoFactorPhase = .chooseMethod

                case .trustedDevice(let error):
                    self.selectedDelivery = .trustedDevice
                    self.availablePhones = []
                    // If Apple already asked for code entry (error present after push),
                    // go straight to enterCode; otherwise first request approval.
                    if let error, !error.isEmpty {
                        self.twoFactorTitle = "Enter code"
                        self.twoFactorMessage = error
                        self.twoFactorPhase = .enterCode
                    } else {
                        self.twoFactorTitle = "Trusted device"
                        self.twoFactorMessage = "Tap Continue so Apple can send a prompt to your iPhone/Mac. Approve it there, then you'll enter the code."
                        self.twoFactorPhase = .chooseMethod
                    }

                case .sms(let phones, let activeID, let error):
                    self.availablePhones = phones
                    self.selectedDelivery = .sms
                    self.selectedPhoneID = activeID.isEmpty ? (phones.first?.id ?? "") : activeID
                    if let error, error.lowercased().contains("code") || error.lowercased().contains("incorrect") {
                        self.twoFactorTitle = "SMS code"
                        self.twoFactorMessage = error
                        self.twoFactorPhase = .enterCode
                    } else if error == nil && activeID.isEmpty == false {
                        // Code was requested — show enter field
                        self.twoFactorTitle = "Enter SMS code"
                        self.twoFactorMessage = "Enter the 6-digit code Apple sent by text message."
                        self.twoFactorPhase = .enterCode
                    } else {
                        self.twoFactorTitle = "Send SMS code"
                        self.twoFactorMessage = error ?? "Tap Continue to request an SMS code."
                        self.twoFactorPhase = .chooseMethod
                    }

                case .voice(let phones, let activeID, let error):
                    self.availablePhones = phones
                    self.selectedDelivery = .voice
                    self.selectedPhoneID = activeID.isEmpty ? (phones.first?.id ?? "") : activeID
                    if error != nil {
                        self.twoFactorTitle = "Voice code"
                        self.twoFactorMessage = error ?? "Enter the code from the call."
                        self.twoFactorPhase = .enterCode
                    } else {
                        self.twoFactorTitle = "Request voice call"
                        self.twoFactorMessage = "Tap Continue so Apple can call you with a code."
                        self.twoFactorPhase = .chooseMethod
                    }
                }
            }
        }
    }

    /// Step 1: request delivery (trusted device / SMS / voice). Closes sheet; SideSign will call back for code.
    func requestDelivery() {
        guard let continuation = pendingVerification else { return }
        pendingVerification = nil
        twoFactorPhase = .waitingForDelivery
        status = "Waiting for Apple verification…"

        switch selectedDelivery {
        case .trustedDevice:
            continuation.resume(returning: .requestTrustedDevice)
        case .sms:
            let phone = selectedPhoneID.isEmpty ? availablePhones.first?.id : selectedPhoneID
            if let phone {
                continuation.resume(returning: .requestSMS(phoneID: phone))
            } else {
                continuation.resume(returning: .cancel)
                twoFactorPhase = .none
            }
        case .voice:
            let phone = selectedPhoneID.isEmpty ? availablePhones.first?.id : selectedPhoneID
            if let phone {
                continuation.resume(returning: .requestVoice(phoneID: phone))
            } else {
                continuation.resume(returning: .cancel)
                twoFactorPhase = .none
            }
        }
    }

    /// Step 2: submit the 6-digit code.
    func submitCode() {
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let continuation = pendingVerification else { return }
        pendingVerification = nil
        twoFactorPhase = .none
        continuation.resume(returning: .verificationCode(code))
    }

    /// If already in enterCode and user somehow needs re-request.
    func submitVerification() {
        if twoFactorPhase == .enterCode {
            submitCode()
        } else {
            requestDelivery()
        }
    }

    func cancelVerification() {
        let continuation = pendingVerification
        pendingVerification = nil
        twoFactorPhase = .none
        twoFactorTitle = ""
        twoFactorMessage = ""
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
        let raw: String
        if let error = error as? LocalizedError, let message = error.errorDescription {
            raw = message
        } else {
            raw = String(describing: error)
        }
        let lower = raw.lowercased()
        if lower.contains("434") || lower.contains("http 434") {
            return "Anisette server returned 434 (unavailable / rate-limited). Pick another server from the list and try again."
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "Network timeout. Check connection or try another Anisette server."
        }
        if lower.contains("incorrect") && lower.contains("credential") {
            return "Wrong Apple ID or password."
        }
        if lower.contains("verification") && lower.contains("incorrect") {
            return "Incorrect verification code. Try again."
        }
        return String(raw.prefix(400))
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

                        credentialsCard
                        teamsCard

                        Text(model.status)
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 4)
                            .animation(.easeOut(duration: 0.25), value: model.status)

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

                        Text("Password is never saved. If a server shows 434, pick another from the list. Free Apple ID certs last ~7 days.")
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
                if model.selectedServerAddress.isEmpty,
                   let first = catalog.servers.first {
                    model.selectedServerAddress = first.address
                }
            }
            .sheet(isPresented: Binding(
                get: { model.showTwoFactorSheet },
                set: { if !$0 { model.cancelVerification() } }
            )) {
                TwoFactorSheet(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Credentials

    private var credentialsCard: some View {
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
                serverListExpanded
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
    }

    private var serverListExpanded: some View {
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
                Text(catalog.lastError ?? "No servers.")
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

    @ViewBuilder
    private var teamsCard: some View {
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
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var selectedServerName: String {
        if let match = catalog.servers.first(where: { $0.address == model.selectedServerAddress }) {
            return match.name
        }
        if model.selectedServerAddress.isEmpty { return "Select a server" }
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

// MARK: - 2FA sheet (request → approve → enter code)

struct TwoFactorSheet: View {
    @ObservedObject var model: SideSignAppleAccountProvider

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text(model.twoFactorTitle)
                        .font(.title3.bold())
                        .foregroundColor(Theme.textPrimary)

                    Text(model.twoFactorMessage)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    if model.twoFactorPhase == .chooseMethod {
                        methodPicker

                        if model.selectedDelivery != .trustedDevice, !model.availablePhones.isEmpty {
                            phonePicker
                        }

                        Button {
                            Haptic.medium()
                            model.requestDelivery()
                        } label: {
                            Text(primaryActionTitle)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.white)
                                .background(Theme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if model.twoFactorPhase == .waitingForDelivery {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Waiting for Apple… Approve on your device if prompted.")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.vertical, 8)
                    }

                    if model.twoFactorPhase == .enterCode {
                        TextField("6-digit code", text: $model.verificationCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Theme.glassStroke, lineWidth: 1)
                                    }
                            }
                            .foregroundColor(Theme.textPrimary)

                        Button {
                            Haptic.medium()
                            model.submitCode()
                        } label: {
                            Text("Confirm code")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.white)
                                .background(Theme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
                        .opacity(model.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 ? 0.5 : 1)
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancelVerification() }
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var primaryActionTitle: String {
        switch model.selectedDelivery {
        case .trustedDevice: return "Send prompt to my devices"
        case .sms: return "Send SMS code"
        case .voice: return "Call me with code"
        }
    }

    private var methodPicker: some View {
        VStack(spacing: 8) {
            methodRow(.trustedDevice, title: "Trusted device", icon: "iphone")
            if !model.availablePhones.isEmpty {
                methodRow(.sms, title: "Text message (SMS)", icon: "message.fill")
                methodRow(.voice, title: "Phone call", icon: "phone.fill")
            }
        }
    }

    private func methodRow(_ mode: TwoFactorDeliveryMode, title: String, icon: String) -> some View {
        let selected = model.selectedDelivery == mode
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                model.selectedDelivery = mode
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(selected ? Theme.primaryLight : Theme.textSecondary)
                    .frame(width: 28)
                Text(title)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.primaryLight)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Theme.primary.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Theme.primaryLight.opacity(0.35) : Theme.glassStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var phonePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phone number")
                .font(.caption.weight(.medium))
                .foregroundColor(Theme.textSecondary)
            ForEach(model.availablePhones) { phone in
                Button {
                    model.selectedPhoneID = phone.id
                } label: {
                    HStack {
                        Text(phone.number)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        if model.selectedPhoneID == phone.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.primaryLight)
                        }
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
