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
    @Published var selectedTeamID = "" {
        didSet { UserDefaults.standard.set(selectedTeamID, forKey: "PurpleKit.selectedTeamID") }
    }
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
        selectedTeamID = UserDefaults.standard.string(forKey: "PurpleKit.selectedTeamID") ?? ""
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
            Task {
                await loadTeams()
                if !hasCertificate, !teams.isEmpty {
                    await createDevelopmentCertificate()
                }
            }
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
            // Auto-issue development cert so user can Sign & Install without extra taps.
            if !hasCertificate, !teams.isEmpty {
                status = "Requesting development certificate…"
                await createDevelopmentCertificate()
            }
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
            if !teams.contains(where: { $0.identifier == selectedTeamID }) {
                selectedTeamID = teams.first?.identifier ?? ""
            }
            let teamLabel = teams.first(where: { $0.identifier == selectedTeamID })?.name
            CertificateStore.shared.applyAuthenticatedSession(email: authSession.account.appleID, team: teamLabel)
            status = "Signed in as \(authSession.account.appleID). \(teams.count) team(s)."
        } catch {
            status = "Signed in, but team loading failed: \(Self.safeError(error))"
        }
    }

    func createDevelopmentCertificate() async {
        guard !DeviceInstaller.shared.isWorking && !IPASigningService.shared.isWorking else {
            status = "Дождись завершения подписи или установки."
            return
        }
        guard let authSession, let team = teams.first(where: { $0.identifier == selectedTeamID }) ?? teams.first else {
            status = "Сначала войди — team не загружен."
            return
        }
        if selectedTeamID.isEmpty { selectedTeamID = team.identifier }
        isBusy = true
        defer { isBusy = false }
        do {
            status = "Запрашиваю development certificate у Apple…"
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
            UserDefaults.standard.set(certificateName, forKey: "PurpleKit.certName")
            if let certificateExpires {
                UserDefaults.standard.set(certificateExpires.timeIntervalSince1970, forKey: "PurpleKit.certExpires")
            }
            CertificateStore.shared.applyCertificate(name: certificateName, expires: certificateExpires)
            CertificateStore.shared.applyAuthenticatedSession(email: authSession.account.appleID, team: team.name)
            status = "Сертификат готов: \(certificateName). Можно Sign & Install."
        } catch {
            let msg = Self.safeError(error)
            let lower = msg.lowercased()
            if lower.contains("maximum") || lower.contains("limit") || lower.contains("already") {
                status = "Лимит сертификатов Apple. Удали старые на developer.apple.com, затем Request certificate снова. (\(msg))"
            } else {
                status = "Сертификат не выдан: \(msg)"
            }
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
    @ObservedObject private var catalog = AnisetteServerCatalog.shared
    @State private var showServerList = false

    var body: some View {
        NavigationStack {
            ToolLayout(primaryTitle: model.isBusy ? "Вход…" : "Войти",
                       isBusy: !model.canSignIn,
                       primaryAction: { Task { await model.signIn() } }) {
                SectionHeading(title: "Учётная запись")
                SettingsGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apple ID").font(.caption).foregroundStyle(Theme.secondaryText)
                        TextField("Apple ID", text: $model.appleID)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .frame(minHeight: 44)
                    }
                    .padding(Theme.rowInset)
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Пароль").font(.caption).foregroundStyle(Theme.secondaryText)
                        SecureField("Пароль", text: $model.password)
                            .textContentType(.password)
                            .frame(minHeight: 44)
                    }
                    .padding(Theme.rowInset)
                    SettingsDivider()
                    Button { showServerList = true } label: {
                        SettingsRow(title: "Anisette", value: model.selectedServerAddress.isEmpty ? "Выбрать сервер" : model.selectedServerAddress)
                    }
                    .buttonStyle(.plain)
                }

                if model.twoFactorPhase == .waitingForDelivery {
                    ProgressView("Подтверди вход в системном окне Apple.")
                }

                if model.account != nil {
                    SectionHeading(title: "Команда и сертификат")
                    SettingsGroup {
                        if !model.teams.isEmpty {
                            Picker("Команда", selection: $model.selectedTeamID) {
                                ForEach(model.teams, id: \.identifier) { team in
                                    Text(team.name).tag(team.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(Theme.rowInset)
                            SettingsDivider()
                            Button {
                                Task { await model.createDevelopmentCertificate() }
                            } label: {
                                SettingsRow(title: model.hasCertificate ? "Перевыпустить сертификат" : "Запросить сертификат")
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isBusy)
                        }
                    }
                    Button("Выйти", role: .destructive) { model.signOut() }
                        .frame(minHeight: 44)
                }
                Text(model.status).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
            }
            .navigationTitle("Apple ID")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }.frame(minHeight: 44)
                }
            }
            .sheet(isPresented: $showServerList) { serverList }
            .sheet(isPresented: Binding(
                get: { model.showTwoFactorSheet },
                set: { if !$0 { model.cancelVerification() } }
            )) { verification }
        }
    }

    private var serverList: some View {
        NavigationStack {
            ToolLayout {
                SettingsGroup {
                    ForEach(catalog.servers, id: \.address) { server in
                        Button {
                            model.selectedServerAddress = server.address
                            showServerList = false
                        } label: {
                            SettingsRow(title: server.name, value: server.address, showsChevron: false)
                        }
                        .buttonStyle(.plain)
                        if server.id != catalog.servers.last?.id { SettingsDivider() }
                    }
                }
                if catalog.isLoading { ProgressView("Загрузка серверов…") }
                if let error = catalog.lastError {
                    Text(error).font(.subheadline).foregroundStyle(Theme.error)
                }
            }
            .navigationTitle("Серверы Anisette")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showServerList = false }.frame(minHeight: 44)
                }
            }
            .task { await catalog.refresh() }
        }
    }

    private var verification: some View {
        NavigationStack {
            ToolLayout(primaryTitle: model.twoFactorPhase == .enterCode ? "Подтвердить" : "Продолжить",
                       primaryAction: {
                           if model.twoFactorPhase == .enterCode { model.submitCode() }
                           else { model.requestDelivery() }
                       }) {
                Text(model.twoFactorMessage).font(.body).foregroundStyle(Theme.secondaryText)
                SettingsGroup {
                    if model.twoFactorPhase == .enterCode {
                        InputField(placeholder: "Код подтверждения", text: $model.verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } else if model.twoFactorPhase == .chooseMethod {
                        Picker("Способ", selection: $model.selectedDelivery) {
                            Text("Доверенное устройство").tag(TwoFactorDeliveryMode.trustedDevice)
                            Text("SMS").tag(TwoFactorDeliveryMode.sms)
                            Text("Звонок").tag(TwoFactorDeliveryMode.voice)
                        }
                        .pickerStyle(.menu)
                        .padding(Theme.rowInset)
                    }
                }
            }
            .navigationTitle(model.twoFactorTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { model.cancelVerification() }.frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
