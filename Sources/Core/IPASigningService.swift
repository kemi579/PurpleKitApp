import Foundation
import UIKit
import SideSign

@MainActor
final class IPASigningService: ObservableObject {
    static let shared = IPASigningService()

    @Published private(set) var isWorking = false
    @Published private(set) var progressText = ""
    @Published var deviceUDID: String {
        didSet { UserDefaults.standard.set(deviceUDID, forKey: "PurpleKit.deviceUDID") }
    }

    private let portal = DeveloperPortal.shared

    private init() {
        let saved = UserDefaults.standard.string(forKey: "PurpleKit.deviceUDID") ?? ""
        deviceUDID = SideloadValidation.isValidUDID(saved) ? saved : ""
    }

    /// Validates local credentials without creating certificates or touching the portal.
    func validateCredentials() throws {
        _ = try loadAuthSession()
        let keys = try loadKeyStore()
        guard keys.certificate.expiryDate > Date() else { throw SignError.certificateExpired }
    }

    func sign(ipaURL: URL) async throws -> URL {
        guard !isWorking else { throw SignError.busy }
        isWorking = true
        defer {
            isWorking = false
            progressText = ""
        }

        progressText = "Проверка сессии Apple ID…"
        let auth = try loadAuthSession()
        let keyStore = try loadKeyStore()
        guard keyStore.certificate.expiryDate > Date() else { throw SignError.certificateExpired }
        guard SideloadValidation.isValidUDID(deviceUDID) else { throw SignError.missingUDID }

        progressText = "Проверка команды и сертификата…"
        let teams: [Team]
        do {
            teams = try await portal.fetchTeams(for: auth.account, session: auth.session)
        } catch {
            throw mapSessionError(error)
        }
        let selectedID = UserDefaults.standard.string(forKey: "PurpleKit.selectedTeamID") ?? ""
        let selected = teams.first { $0.identifier == selectedID }
        guard let team = selected ?? (selectedID.isEmpty && teams.count == 1 ? teams.first : nil) else {
            throw teams.isEmpty ? SignError.noTeam : SignError.selectTeam
        }
        let certificates: [X509Certificate]
        do {
            certificates = try await portal.fetchCertificates(for: team, session: auth.session)
        } catch {
            throw mapSessionError(error)
        }
        guard let portalCertificate = certificates.first(where: {
            $0.serialNumber.caseInsensitiveCompare(keyStore.certificate.serialNumber) == .orderedSame
        }) else {
            throw SignError.certificateTeamMismatch
        }
        let certificateID = portalCertificate.identifier ?? portalCertificate.serialNumber
        CertificateStore.shared.applyAuthenticatedSession(email: auth.account.appleID, team: team.name)
        CertificateStore.shared.applyCertificate(name: keyStore.certificate.name, expires: keyStore.certificate.expiryDate)

        progressText = "Распаковка и проверка IPA…"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("PurpleKitSign-\(UUID().uuidString)", isDirectory: true)
        // The workspace is unique to this operation and removed on every exit.
        defer { try? FileManager.default.removeItem(at: work) }
        let appURL = try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            return try fm.unzipAppBundle(at: ipaURL, to: work)
        }.value
        guard let sourceApp = AppBundle(fileURL: appURL) else { throw SignError.missingBundleID }
        progressText = "Подготовка идентификаторов приложения…"
        for bundle in sourceApp.allAppBundles {
            guard let identifier = SideloadValidation.resignedBundleID(
                originalRoot: sourceApp.bundleIdentifier,
                bundleID: bundle.bundleIdentifier, teamID: team.identifier
            ) else { throw SignError.invalidBundleID }
            try bundle.updateInfoPlist(with: ["CFBundleIdentifier": identifier])
        }
        guard let app = AppBundle(fileURL: appURL) else { throw SignError.missingBundleID }

        progressText = "Регистрация устройства…"
        let device = try await ensureDevice(team: team, session: auth.session)
        var profiles: [ProvisioningProfile] = []
        // Extensions need profiles for their own bundle IDs. Never reuse the main app profile.
        for bundle in app.allAppBundles {
            try Task.checkCancellation()
            progressText = "Профиль: \(bundle.bundleIdentifier)…"
            let appID = try await ensureAppID(name: bundle.name, bundleID: bundle.bundleIdentifier, team: team, session: auth.session)
            let profile = try await ensureProfile(
                appID: appID, certificateID: certificateID,
                certificateSerial: keyStore.certificate.serialNumber,
                device: device, team: team, session: auth.session
            )
            profiles.append(profile)
        }

        progressText = "Подпись приложения и расширений…"
        let bundleSigner = AppBundleSigner(team: team, keyStore: keyStore)
        try await bundleSigner.signApp(at: appURL, provisioningProfiles: profiles)

        progressText = "Сохранение подписанного IPA…"
        let output = try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let zipped = try fm.zipAppBundle(at: appURL, compressionLevel: .none)
            defer { try? fm.removeItem(at: zipped) }
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = docs.appendingPathComponent("SignedIPAs", isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "\(appURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString)-signed.ipa"
            let result = directory.appendingPathComponent(name)
            try fm.moveItem(at: zipped, to: result)
            return result
        }.value
        progressText = "IPA подписан."
        return output
    }

    private func mapSessionError(_ error: Error) -> Error {
        let message = String(describing: error).lowercased()
        if message.contains("1100") || message.contains("session has expired") || message.contains("please log in") {
            try? KeychainVault.delete(account: "sidesign-auth-session")
            CertificateStore.shared.logout()
            return SignError.sessionExpired
        }
        return error
    }

    private func loadAuthSession() throws -> AuthSession {
        guard let data = try KeychainVault.load(account: "sidesign-auth-session"),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            throw SignError.notSignedIn
        }
        guard session.session.isValid else {
            try? KeychainVault.delete(account: "sidesign-auth-session")
            CertificateStore.shared.logout()
            throw SignError.sessionExpired
        }
        return session
    }

    private func loadKeyStore() throws -> KeyStore {
        guard let p12 = try KeychainVault.load(account: "sidesign-development-certificate-p12"),
              let passwordData = try KeychainVault.load(account: "sidesign-development-certificate-password"),
              let password = String(data: passwordData, encoding: .utf8) else {
            throw SignError.noCertificate
        }
        return try KeyStore(p12Data: p12, password: password)
    }

    private func ensureDevice(team: Team, session: Session) async throws -> Device {
        let udid = deviceUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SideloadValidation.isValidUDID(udid) else { throw SignError.missingUDID }
        do {
            let devices = try await portal.fetchDevices(for: team, types: .all, session: session)
            if let existing = devices.first(where: { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }) {
                return existing
            }
            return try await portal.registerDevice(
                name: UIDevice.current.name, identifier: udid, type: .iPhone,
                team: team, session: session
            )
        } catch {
            throw mapSessionError(error)
        }
    }

    private func ensureAppID(name: String, bundleID: String, team: Team, session: Session) async throws -> AppID {
        do {
            let existing = try await portal.fetchAppIDs(for: team, session: session)
            if let found = existing.first(where: { $0.bundleIdentifier == bundleID }) { return found }
            return try await portal.addAppID(
                withName: String(name.prefix(30)), bundleIdentifier: bundleID, team: team, session: session
            )
        } catch {
            throw mapSessionError(error)
        }
    }

    private func ensureProfile(
        appID: AppID, certificateID: String, certificateSerial: String,
        device: Device, team: Team, session: Session
    ) async throws -> ProvisioningProfile {
        func matches(_ profile: ProvisioningProfile) -> Bool {
            SideloadValidation.profileMatches(
                bundleID: appID.bundleIdentifier, teamID: team.identifier,
                udid: deviceUDID, certificateSerial: certificateSerial,
                profileBundleID: profile.bundleIdentifier, profileTeamID: profile.teamIdentifier,
                profileDevices: profile.deviceIDs,
                profileCertificateSerials: profile.certificates.map(\.serialNumber),
                expiration: profile.expirationDate
            )
        }

        // Xcode team profiles may include all registered devices/certificates.
        // Validate their actual contents before allowing the signer to use them.
        let downloaded: ProvisioningProfile?
        do {
            downloaded = try await portal.downloadProvisioningProfile(
                for: appID, isTeamProfile: true, deviceType: .iPhone, team: team, session: session
            )
        } catch {
            let mapped = mapSessionError(error)
            if let signError = mapped as? SignError, signError == .sessionExpired { throw mapped }
            downloaded = nil
        }
        if let downloaded, matches(downloaded) { return downloaded }

        do {
            let created = try await portal.createProvisioningProfile(
                name: "PurpleKit \(appID.bundleIdentifier)",
                appID: appID, certificateIDs: [certificateID],
                deviceIDs: [device.deviceID ?? device.identifier], team: team, session: session
            )
            guard matches(created) else { throw SignError.invalidProfile }
            return created
        } catch {
            throw mapSessionError(error)
        }
    }

    enum SignError: LocalizedError, Equatable {
        case busy, notSignedIn, sessionExpired, noCertificate, certificateExpired
        case noTeam, selectTeam, certificateTeamMismatch, missingUDID, missingBundleID, invalidBundleID, invalidProfile

        var errorDescription: String? {
            switch self {
            case .busy: return "Другая операция подписи уже выполняется."
            case .notSignedIn: return "Подключи Apple ID в настройках."
            case .sessionExpired: return "Сессия Apple ID истекла. Войди заново в настройках."
            case .noCertificate: return "Нет сертификата разработки. Запроси его в настройках Apple ID."
            case .certificateExpired: return "Сертификат истёк. Запроси новый в настройках Apple ID."
            case .noTeam: return "У Apple ID нет доступной команды разработчика."
            case .selectTeam: return "Выбери доступную команду в настройках Apple ID."
            case .certificateTeamMismatch: return "Сертификат не найден в выбранной команде Apple или отозван. Запроси сертификат для этой команды."
            case .missingUDID: return "Нужен настоящий UDID. Импортируй pairing и включи локальный VPN либо введи UDID в настройках."
            case .missingBundleID: return "Не удалось прочитать приложение внутри IPA."
            case .invalidBundleID: return "Не удалось подготовить согласованные Bundle ID приложения и расширений."
            case .invalidProfile: return "Профиль не подходит для этого приложения, устройства или сертификата."
            }
        }
    }
}
