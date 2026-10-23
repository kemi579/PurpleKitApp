import Foundation
import UIKit
import SideSign

@MainActor
final class IPASigningService: ObservableObject {
    static let shared = IPASigningService()

    @Published private(set) var isWorking = false
    @Published private(set) var progressText = ""
    @Published var deviceUDID: String {
        didSet { UserDefaults.standard.set(deviceUDID, forKey: Keys.udid) }
    }

    private enum Keys {
        static let udid = "PurpleKit.deviceUDID"
        static let certID = "PurpleKit.certPortalID"
    }

    private let portal = DeveloperPortal.shared
    private let fm = FileManager.default

    private init() {
        deviceUDID = UserDefaults.standard.string(forKey: Keys.udid) ?? ""
        // Best-effort placeholder — real device UDID for provisioning still needs pairing/muxer or paste.
        if deviceUDID.isEmpty {
            // NOT a real Apple UDID; only avoids empty field. User/muxer must set real one for install.
            deviceUDID = UIDevice.current.identifierForVendor?.uuidString ?? ""
        }
    }

    func sign(ipaURL: URL) async throws -> URL {
        isWorking = true
        defer {
            isWorking = false
            progressText = ""
        }

        progressText = "Loading Apple session…"
        let auth: AuthSession
        do {
            auth = try loadAuthSession()
        } catch {
            throw error
        }

        let keyStore: KeyStore
        do {
            keyStore = try loadKeyStore()
        } catch {
            throw error
        }

        progressText = "Loading team…"
        let teams: [Team]
        do {
            teams = try await portal.fetchTeams(for: auth.account, session: auth.session)
        } catch {
            throw mapSessionError(error)
        }
        guard let team = teams.first else { throw SignError.noTeam }

        progressText = "Preparing workspace…"
        let workDir = try makeWorkDir()
        defer { try? fm.removeItem(at: workDir) }

        progressText = "Unpacking IPA…"
        let appURL = try fm.unzipAppBundle(at: ipaURL, to: workDir)

        progressText = "Reading bundle ID…"
        let bundleID = try readBundleID(appURL: appURL)
        let appName = appURL.deletingPathExtension().lastPathComponent

        progressText = "Ensuring device is registered…"
        let device = try await ensureDevice(team: team, session: auth.session)

        progressText = "Ensuring App ID…"
        let appID = try await ensureAppID(name: appName, bundleID: bundleID, team: team, session: auth.session)

        progressText = "Fetching provisioning profile…"
        let profile = try await ensureProfile(appID: appID, keyStore: keyStore, device: device, team: team, session: auth.session)

        progressText = "Signing \(bundleID)…"
        let signer = AppBundleSigner(team: team, keyStore: keyStore)
        try await signer.signApp(at: appURL, provisioningProfiles: [profile])

        progressText = "Packaging signed IPA…"
        let signedTemp = try fm.zipAppBundle(at: appURL, compressionLevel: .none)
        let outDir = try signedDirectory()
        let outName = "\(appName)-signed.ipa"
        let outURL = outDir.appendingPathComponent(outName)
        if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
        try fm.moveItem(at: signedTemp, to: outURL)

        progressText = "Signed successfully."
        return outURL
    }

    private func mapSessionError(_ error: Error) -> Error {
        let raw = String(describing: error).lowercased()
        let msg = (error as? LocalizedError)?.errorDescription?.lowercased() ?? raw
        if msg.contains("1100") || msg.contains("session has expired") || msg.contains("please log in") || raw.contains("1100") {
            // Wipe dead session so UI asks for login again
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
        if !session.session.isValid {
            try? KeychainVault.delete(account: "sidesign-auth-session")
            CertificateStore.shared.logout()
            throw SignError.sessionExpired
        }
        return session
    }

    private func loadKeyStore() throws -> KeyStore {
        guard let p12 = try KeychainVault.load(account: "sidesign-development-certificate-p12"),
              let passData = try KeychainVault.load(account: "sidesign-development-certificate-password"),
              let password = String(data: passData, encoding: .utf8) else {
            throw SignError.noCertificate
        }
        return try KeyStore(p12Data: p12, password: password)
    }

    private func ensureDevice(team: Team, session: Session) async throws -> Device {
        var udid = deviceUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer muxer UDID when available
        if let muxerUDID = DeviceInstaller.shared.deviceUDIDFromMuxer, !muxerUDID.isEmpty {
            udid = muxerUDID
            deviceUDID = muxerUDID
        }
        guard !udid.isEmpty else { throw SignError.missingUDID }
        // identifierForVendor looks like UUID — Apple portal needs real 25-char UDID
        if udid.count == 36, udid.contains("-") {
            throw SignError.missingUDID
        }

        let devices: [Device]
        do {
            devices = try await portal.fetchDevices(for: team, types: .all, session: session)
        } catch {
            throw mapSessionError(error)
        }
        if let existing = devices.first(where: { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }) {
            return existing
        }
        do {
            return try await portal.registerDevice(
                name: UIDevice.current.name,
                identifier: udid,
                type: .iPhone,
                team: team,
                session: session
            )
        } catch {
            let again = try await portal.fetchDevices(for: team, types: .all, session: session)
            if let existing = again.first(where: { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }) {
                return existing
            }
            throw mapSessionError(error)
        }
    }

    private func ensureAppID(name: String, bundleID: String, team: Team, session: Session) async throws -> AppID {
        do {
            let existing = try await portal.fetchAppIDs(for: team, session: session)
            if let found = existing.first(where: { $0.bundleIdentifier == bundleID }) { return found }
            let safeName = String(name.prefix(30))
            return try await portal.addAppID(withName: safeName, bundleIdentifier: bundleID, team: team, session: session)
        } catch {
            throw mapSessionError(error)
        }
    }

    private func ensureProfile(
        appID: AppID,
        keyStore: KeyStore,
        device: Device,
        team: Team,
        session: Session
    ) async throws -> ProvisioningProfile {
        do {
            return try await portal.downloadProvisioningProfile(
                for: appID,
                isTeamProfile: true,
                deviceType: .iPhone,
                team: team,
                session: session
            )
        } catch {
            let certID = keyStore.certificate.identifier
                ?? UserDefaults.standard.string(forKey: Keys.certID)
                ?? keyStore.certificate.serialNumber
            let deviceID = device.deviceID ?? device.identifier
            do {
                return try await portal.createProvisioningProfile(
                    name: "PurpleKit \(appID.bundleIdentifier)",
                    appID: appID,
                    certificateIDs: [certID],
                    deviceIDs: [deviceID],
                    team: team,
                    session: session
                )
            } catch {
                throw mapSessionError(error)
            }
        }
    }

    private func readBundleID(appURL: URL) throws -> String {
        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any],
              let bid = dict["CFBundleIdentifier"] as? String,
              !bid.isEmpty else {
            throw SignError.missingBundleID
        }
        return bid
    }

    private func makeWorkDir() throws -> URL {
        let base = fm.temporaryDirectory.appendingPathComponent("PurpleKitSign-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func signedDirectory() throws -> URL {
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("SignedIPAs", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    enum SignError: LocalizedError {
        case notSignedIn
        case sessionExpired
        case noCertificate
        case noTeam
        case missingUDID
        case missingBundleID

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Войди в Apple ID (Настройки)."
            case .sessionExpired:
                return "Сессия истекла (1100). Зайди в Apple ID заново в Настройках."
            case .noCertificate:
                return "Нет development certificate. Зайди в Apple ID — сертификат запросится сам."
            case .noTeam:
                return "Нет developer team на этом Apple ID."
            case .missingUDID:
                return "Нужен настоящий UDID устройства (не UUID). Вставь из Finder/Xcode или получи через pairing + minimuxer."
            case .missingBundleID:
                return "Не прочитан CFBundleIdentifier."
            }
        }
    }
}
