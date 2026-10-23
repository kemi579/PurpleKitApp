import Foundation
import SwiftUI
import SideSign

enum TwoFactorPhase: Equatable {
    case none, chooseMethod, waitingForDelivery, enterCode
}

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

    @Published var twoFactorPhase: TwoFactorPhase = .none
    @Published var twoFactorTitle = ""
    @Published var twoFactorMessage = ""
    @Published var verificationCode = ""
    @Published var selectedDelivery: TwoFactorDeliveryMode = .trustedDevice
    @Published private(set) var availablePhones: [TrustedPhoneNumber] = []
    @Published var selectedPhoneID = ""

    private var pendingVerification: CheckedContinuation<TwoFactorResponse, Never>?
    private var didRequestTrustedDevice = false
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
            CertificateStore.shared.applyAuthenticatedSession(email: session.account.appleID, team: nil)
            if hasCertificate {
                CertificateStore.shared.applyCertificate(name: certificateName, expires: certificateExpires)
            }
            Task { await loadTeams() }
        }
    }

    var canSignIn: Bool {
        !isBusy && !appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && validAnisetteURL != nil
    }

    var showTwoFactorSheet: Bool {
        twoFactorPhase == .enterCode || twoFactorPhase == .chooseMethod
    }

    private var validAnisetteURL: URL? {
        guard let url = URL(string: selectedServerAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    func signIn() async {
        guard canSignIn, let serverURL = validAnisetteURL else {
            status = "Enter Apple ID, password, and pick an Anisette server."
            return
        }
        isBusy = true
        status = "Fetching Anisette data…"
        twoFactorPhase = .none
        didRequestTrustedDevice = false
        defer { isBusy = false; password = "" }
        UserDefaults.standard.set(serverURL.absoluteString, forKey: Self.selectedServerKey)
        do {
            let (anisetteData, _) = try await anisette.fetchAnisetteData(mode: .remote(server: serverURL), identifier: UUID())
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
            twoFactorPhase = .none
            try KeychainVault.save(Data(appleID.trimmingCharacters(in: .whitespacesAndNewlines).utf8), account: "apple-id-email")
            try KeychainVault.save(try JSONEncoder().encode(result), account: "sidesign-auth-session")
            CertificateStore.shared.applyAuthenticatedSession(email: result.account.appleID, team: nil)
            status = "Signed in. Loading teams…"
            await loadTeams()
        } catch {
            status = Self.safeError(error)
            authSession = nil
            account = nil
            teams = []
            twoFactorPhase = .none
            try? KeychainVault.delete(account: "sidesign-auth-session")
            CertificateStore.shared.logout()
        }
    }

    private func handleVerification(_ request: TwoFactorRequest) async -> TwoFactorResponse {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.verificationCode = ""
                switch request {
                case .selectDeliveryMethod(let preferred, let phones):
                    self.availablePhones = phones
                    self.selectedDelivery = preferred
                    self.selectedPhoneID = phones.first?.id ?? ""
                    if preferred == .trustedDevice || phones.isEmpty {
                        self.respondTrustedDevice(continuation: continuation)
                    } else {
                        self.pendingVerification = continuation
                        self.twoFactorTitle = "Способ проверки"
                        self.twoFactorMessage = "Выбери SMS или звонок."
                        self.twoFactorPhase = .chooseMethod
                    }
                case .trustedDevice(let error):
                    self.selectedDelivery = .trustedDevice
                    self.availablePhones = []
                    if let error, !error.isEmpty {
                        self.pendingVerification = continuation
                        self.twoFactorTitle = "Код подтверждения"
                        self.twoFactorMessage = error
                        self.twoFactorPhase = .enterCode
                        self.status = "Неверный код? Введи ещё раз."
                        return
                    }
                    self.respondTrustedDevice(continuation: continuation)
                case .sms(let phones, let activeID, let error):
                    self.availablePhones = phones
                    self.selectedDelivery = .sms
                    self.selectedPhoneID = activeID.isEmpty ? (phones.first?.id ?? "") : activeID
                    let needsCode = (error != nil && !(error!.isEmpty)) || (!activeID.isEmpty && error == nil)
                    if needsCode {
                        self.pendingVerification = continuation
                        self.twoFactorTitle = "SMS код"
                        self.twoFactorMessage = error ?? "Введи код из SMS."
                        self.twoFactorPhase = .enterCode
                        return
                    }
                    if let phone = phones.first(where: { $0.id == self.selectedPhoneID }) ?? phones.first {
                        self.pendingVerification = nil
                        self.twoFactorPhase = .waitingForDelivery
                        self.status = "SMS запрошен."
                        continuation.resume(returning: .requestSMS(phoneID: phone.id))
                    } else {
                        self.pendingVerification = continuation
                        self.twoFactorTitle = "SMS"
                        self.twoFactorMessage = "Нет номеров."
                        self.twoFactorPhase = .chooseMethod
                    }
                case .voice(let phones, let activeID, let error):
                    self.availablePhones = phones
                    self.selectedDelivery = .voice
                    self.selectedPhoneID = activeID.isEmpty ? (phones.first?.id ?? "") : activeID
                    if let error, !error.isEmpty {
                        self.pendingVerification = continuation
                        self.twoFactorTitle = "Код"
                        self.twoFactorMessage = error
                        self.twoFactorPhase = .enterCode
                        return
                    }
                    if let phone = phones.first(where: { $0.id == self.selectedPhoneID }) ?? phones.first {
                        self.pendingVerification = nil
                        self.twoFactorPhase = .waitingForDelivery
                        continuation.resume(returning: .requestVoice(phoneID: phone.id))
                    } else {
                        self.pendingVerification = continuation
                        self.twoFactorTitle = "Voice"
                        self.twoFactorMessage = "Нет номеров."
                        self.twoFactorPhase = .chooseMethod
                    }
                }
            }
        }
    }

    private func respondTrustedDevice(continuation: CheckedContinuation<TwoFactorResponse, Never>) {
        if !didRequestTrustedDevice {
            didRequestTrustedDevice = true
            pendingVerification = nil
            twoFactorPhase = .waitingForDelivery
            status = "Нажми Allow на системном окне Apple. Потом введи код здесь."
            continuation.resume(returning: .requestTrustedDevice)
        } else {
            pendingVerification = continuation
            twoFactorTitle = "Код подтверждения"
            twoFactorMessage = "Введи 6-значный код с экрана Apple."
            twoFactorPhase = .enterCode
            status = "Введи код подтверждения."
        }
    }

    func requestDelivery() {
        guard let continuation = pendingVerification else { return }
        pendingVerification = nil
        twoFactorPhase = .waitingForDelivery
        switch selectedDelivery {
        case .trustedDevice:
            if !didRequestTrustedDevice {
                didRequestTrustedDevice = true
                status = "Approve on iPhone…"
                continuation.resume(returning: .requestTrustedDevice)
            } else {
                pendingVerification = continuation
                twoFactorPhase = .enterCode
            }
        case .sms:
            let phone = selectedPhoneID.isEmpty ? availablePhones.first?.id : selectedPhoneID
            if let phone {
                continuation.resume(returning: .requestSMS(phoneID: phone))
            } else {
                twoFactorPhase = .none
                continuation.resume(returning: .cancel)
            }
        case .voice:
            let phone = selectedPhoneID.isEmpty ? availablePhones.first?.id : selectedPhoneID
            if let phone {
                continuation.resume(returning: .requestVoice(phoneID: phone))
            } else {
                twoFactorPhase = .none
                continuation.resume(returning: .cancel)
            }
        }
    }

    func submitCode() {
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let continuation = pendingVerification else { return }
        pendingVerification = nil
        twoFactorPhase = .none
        status = "Verifying code…"
        continuation.resume(returning: .verificationCode(code))
    }

    func cancelVerification() {
        let continuation = pendingVerification
        pendingVerification = nil
        didRequestTrustedDevice = false
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
            CertificateStore.shared.applyAuthenticatedSession(email: authSession.account.appleID, team: teamLabel)
            status = "Signed in as \(authSession.account.appleID). \(teams.count) team(s)."
        } catch {
            status = "Signed in, but team loading failed: \(Self.safeError(error))"
        }
    }

    func createDevelopmentCertificate() async {
        guard let authSession, let team = teams.first(where: { $0.identifier == selectedTeamID }) else {
            status = "Sign in and select a team first."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let keyStore = try await portal.addCertificate(machineName: "PurpleKit", type: .iosDevelopment, to: team, session: authSession.session)
            let p12Password = UUID().uuidString
            let p12 = try keyStore.exportP12(password: p12Password)
            try KeychainVault.save(p12, account: "sidesign-development-certificate-p12")
            try KeychainVault.save(Data(p12Password.utf8), account: "sidesign-development-certificate-password")
            certificateName = keyStore.certificate.name
            certificateExpires = keyStore.certificate.expiryDate
            hasCertificate = true
            UserDefaults.standard.set(certificateName, forKey: "PurpleKit.certName")
            if let certificateExpires {
                UserDefaults.standard.set(certificateExpires.timeIntervalSince1970, forKey: "PurpleKit.certExpires")
            }
            CertificateStore.shared.applyCertificate(name: certificateName, expires: certificateExpires)
            CertificateStore.shared.applyAuthenticatedSession(email: authSession.account.appleID, team: team.name)
            status = "Development certificate issued and saved."
        } catch {
            status = "Certificate request failed: \(Self.safeError(error))"
        }
    }

    func signOut() {
        cancelVerification()
        didRequestTrustedDevice = false
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
        status = "Signed out."
    }

    private static func safeError(_ error: Error) -> String {
        let raw: String
        if let error = error as? LocalizedError, let message = error.errorDescription {
            raw = message
        } else {
            raw = String(describing: error)
        }
        let lower = raw.lowercased()
        if lower.contains("434") { return "Anisette 434 — выбери другой сервер." }
        if lower.contains("timeout") { return "Timeout. Попробуй другой Anisette сервер." }
        if lower.contains("incorrect") && lower.contains("credential") { return "Неверный Apple ID или пароль." }
        if lower.contains("verification") && lower.contains("incorrect") { return "Неверный код." }
        return String(raw.prefix(400))
    }
}

struct AppleDeveloperPortalSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SideSignAppleAccountProvider()
    @StateObject private var catalog = AnisetteServerCatalog.shared
    @State private var showServerList = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Apple ID")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.primaryGradient)

                        TextField("Apple ID", text: $model.appleID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .padding(14)
                            .glassCard(cornerRadius: 14)

                        SecureField("Password", text: $model.password)
                            .padding(14)
                            .glassCard(cornerRadius: 14)

                        Button { showServerList = true } label: {
                            HStack {
                                Text(model.selectedServerAddress.isEmpty ? "Anisette server" : model.selectedServerAddress)
                                    .lineLimit(1)
                                    .foregroundColor(model.selectedServerAddress.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .padding(14)
                            .glassCard(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)

                        if model.twoFactorPhase == .waitingForDelivery {
                            HStack(spacing: 12) {
                                ProgressView().tint(Theme.primaryLight)
                                Text("Ждём Allow на системном окне Apple…")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .padding(14)
                            .glassCard(cornerRadius: 14)
                        }

                        Button {
                            Task { await model.signIn() }
                        } label: {
                            Text(model.isBusy ? "Signing in…" : "Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.white)
                                .background(Theme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!model.canSignIn)
                        .opacity(model.canSignIn ? 1 : 0.5)

                        if model.account != nil {
                            if !model.teams.isEmpty {
                                Picker("Team", selection: $model.selectedTeamID) {
                                    ForEach(model.teams, id: \.identifier) { t in
                                        Text(t.name).tag(t.identifier)
                                    }
                                }
                                .pickerStyle(.menu)

                                Button {
                                    Task { await model.createDevelopmentCertificate() }
                                } label: {
                                    Text(model.hasCertificate ? "Re-issue certificate" : "Request development certificate")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .foregroundColor(.white)
                                        .background(Theme.primary.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            Button(role: .destructive) { model.signOut() } label: {
                                Text("Sign out").frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                        }

                        Text(model.status)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showServerList) {
                NavigationStack {
                    List(catalog.servers, id: \.address) { server in
                        Button {
                            model.selectedServerAddress = server.address
                            showServerList = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(server.name).foregroundColor(.primary)
                                Text(server.address).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Anisette servers")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showServerList = false }
                        }
                    }
                    .task { await catalog.refresh() }
                }
            }
            .sheet(isPresented: Binding(
                get: { model.showTwoFactorSheet },
                set: { if !$0 { model.cancelVerification() } }
            )) {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text(model.twoFactorTitle).font(.title3.weight(.bold))
                        Text(model.twoFactorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        if model.twoFactorPhase == .enterCode {
                            TextField("6-digit code", text: $model.verificationCode)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .multilineTextAlignment(.center)
                                .font(.title2.monospacedDigit())
                                .padding()
                            Button("Submit") { model.submitCode() }
                                .buttonStyle(.borderedProminent)
                        } else if model.twoFactorPhase == .chooseMethod {
                            Picker("Method", selection: $model.selectedDelivery) {
                                Text("Trusted device").tag(TwoFactorDeliveryMode.trustedDevice)
                                Text("SMS").tag(TwoFactorDeliveryMode.sms)
                                Text("Voice").tag(TwoFactorDeliveryMode.voice)
                            }
                            .pickerStyle(.segmented)
                            Button("Continue") { model.requestDelivery() }
                                .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { model.cancelVerification() }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}
