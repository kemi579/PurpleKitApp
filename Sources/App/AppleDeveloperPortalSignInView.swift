import Foundation
import SwiftUI
import SideSign

/// Real Apple Developer Portal authentication backed by SideSign.
/// Passwords are held only for the duration of an explicit sign-in attempt.
@MainActor
final class SideSignAppleAccountProvider: ObservableObject {
    @Published var appleID = ""
    @Published var password = ""
    @Published var anisetteServer = ""
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

    init() {
        appleID = (try? KeychainVault.load(account: "apple-id-email")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        anisetteServer = UserDefaults.standard.string(forKey: "PurpleKit.selectedAnisetteServer") ?? ""
        if let data = try? KeychainVault.load(account: "sidesign-auth-session"),
           let session = try? JSONDecoder().decode(AuthSession.self, from: data),
           session.session.isValid {
            authSession = session
            account = session.account
            status = "Session restored for \(session.account.appleID)."
            Task { await loadTeams() }
        }
    }

    var canSignIn: Bool {
        !isBusy && !appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty && validAnisetteURL != nil
    }

    private var validAnisetteURL: URL? {
        guard let url = URL(string: anisetteServer.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    func signIn() async {
        guard canSignIn, let serverURL = validAnisetteURL else {
            status = "Enter your Apple ID, password, and a trusted HTTPS Anisette server URL."
            return
        }
        isBusy = true
        status = "Preparing Anisette data…"
        defer {
            isBusy = false
            password = ""
        }
        UserDefaults.standard.set(serverURL.absoluteString, forKey: "PurpleKit.selectedAnisetteServer")
        do {
            let (anisetteData, _) = try await anisette.fetchAnisetteData(
                mode: .remote(server: serverURL),
                identifier: UUID()
            )
            status = "Authenticating directly with Apple…"
            let credentialsPassword = password
            let result = try await portal.authenticate(
                appleID: appleID,
                password: credentialsPassword,
                anisetteData: anisetteData,
                xcodeVersion: "26.0",
                verificationHandler: { [weak self] request in
                    guard let self else { return .cancel }
                    return await self.handleVerification(request)
                }
            )
            authSession = result
            account = result.account
            try KeychainVault.save(Data(appleID.trimmingCharacters(in: .whitespacesAndNewlines).utf8), account: "apple-id-email")
            try KeychainVault.save(try JSONEncoder().encode(result), account: "sidesign-auth-session")
            status = "Apple authentication succeeded. Loading development teams…"
            await loadTeams()
        } catch {
            status = Self.safeError(error)
            authSession = nil
            account = nil
            teams = []
            try? KeychainVault.delete(account: "sidesign-auth-session")
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
            status = "Signed in as \(authSession.account.appleID). Found \(teams.count) team(s)."
        } catch {
            status = "Signed in, but team loading failed: \(Self.safeError(error))"
        }
    }

    func createDevelopmentCertificate() async {
        guard let authSession, let team = teams.first(where: { $0.identifier == selectedTeamID }) else {
            status = "Sign in and select a development team first."
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
            status = "Apple issued a development certificate and its private key was saved to this device's Keychain."
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
        status = "Signed out. Saved session and certificate removed."
    }

    private static func safeError(_ error: Error) -> String {
        if let error = error as? LocalizedError, let message = error.errorDescription {
            return String(message.prefix(400))
        }
        return "Authentication failed. Check the network, Anisette server, and Apple account settings."
    }
}

struct AppleDeveloperPortalSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SideSignAppleAccountProvider()
    @State private var showingPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Theme.primaryGradient)
                            .frame(maxWidth: .infinity).padding(.top, 20)
                        Text("Apple Developer Portal")
                            .font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                        Text("Signs in to Apple using SideSign, supports Apple 2FA, loads teams, and can request an Apple Development certificate. Your password is never saved. Use only an Anisette server you trust; it supplies request metadata, while the login exchange is sent to Apple.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        VStack(spacing: 12) {
                            TextField("Apple ID email", text: $model.appleID)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.emailAddress).textFieldStyle(.roundedBorder)
                            SecureField("Apple ID password", text: $model.password)
                                .textFieldStyle(.roundedBorder)
                            TextField("Trusted Anisette HTTPS server URL", text: $model.anisetteServer)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.URL).textFieldStyle(.roundedBorder)
                            Button {
                                Task { await model.signIn() }
                            } label: {
                                HStack {
                                    if model.isBusy { ProgressView().tint(.white) }
                                    Text(model.isBusy ? "Connecting…" : "Sign in with Apple ID").fontWeight(.semibold)
                                }.frame(maxWidth: .infinity).padding(14)
                                    .background(Theme.primaryGradient).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.disabled(!model.canSignIn)
                        }
                        if !model.teams.isEmpty {
                            Text("Developer teams").font(.headline).foregroundStyle(Theme.textPrimary)
                            Picker("Team", selection: $model.selectedTeamID) {
                                ForEach(model.teams, id: \.identifier) { team in
                                    Text("\(team.name) (\(team.type.displayName))").tag(team.identifier)
                                }
                            }.pickerStyle(.menu).tint(Theme.primaryLight)
                            Button {
                                Task { await model.createDevelopmentCertificate() }
                            } label: {
                                Label(model.hasCertificate ? "Create another development certificate" : "Request development certificate", systemImage: "checkmark.seal")
                                    .frame(maxWidth: .infinity).padding(12)
                            }.buttonStyle(.borderedProminent).tint(Theme.primaryLight).disabled(model.isBusy)
                        }
                        if model.hasCertificate {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Certificate saved securely").font(.headline)
                                Text(model.certificateName)
                                if let expiry = model.certificateExpires {
                                    Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                }
                            }.foregroundStyle(Theme.textPrimary).padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Text(model.status).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                        if model.account != nil {
                            Button("Sign out and remove saved session", role: .destructive) {
                                model.signOut()
                            }
                        }
                    }.padding(20)
                }
            }
            .navigationTitle("Apple ID").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .alert(model.verificationPrompt ?? "Apple verification", isPresented: Binding(
                get: { model.verificationPrompt != nil },
                set: { if !$0 { model.cancelVerification() } }
            )) {
                TextField("Verification code (if requested)", text: $model.verificationCode)
                    .keyboardType(.numberPad)
                Button("Continue") { model.submitVerification() }
                Button("Cancel", role: .cancel) { model.cancelVerification() }
            } message: {
                Text("For SMS or voice, enter the code. For trusted-device verification, approve the request first and then continue.")
            }
        }
    }
}
