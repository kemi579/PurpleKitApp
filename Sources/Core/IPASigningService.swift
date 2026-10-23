import Foundation
import UIKit
import SideSign

/// Signs an IPA with the saved development certificate and a provisioning profile
/// from the Apple Developer Portal (via SideSign).
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
    }

    // MARK: - Public API

    /// Sign `ipaURL` → returns URL of signed IPA in Documents/SignedIPAs.
    func sign(ipaURL: URL) async throws -> URL {
        isWorking = true
        defer {
            isWorking = false
            progressText = ""
        }

        progressText = "Loading Apple session…"
        let auth = try loadAuthSession()
        let keyStore = try loadKeyStore()

        progressText = "Loading team…"
        let teams = try await portal.fetchTeams(for: auth.account, session: auth.session)
        guard let team = teams.first else {
            throw SignError.noTeam
        }

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
        let appID = try await ensureAppID(
            name: appName,
            bundleID: bundleID,
            team: team,
            session: auth.session
        )

        progressText = "Fetching provisioning profile…"
        let profile = try await ensureProfile(
            appID: appID,
            keyStore: keyStore,
            device: device,
            team: team,
            session: auth.session
        )

        progressText = "Signing \(bundleID)…"
        let signer = AppBundleSigner(team: team, keyStore: keyStore)
        try await signer.signApp(at: appURL, provisioningProfiles: [profile])

        progressText = "Packaging signed IPA…"
        let signedTemp = try fm.zipAppBundle(at: appURL, compressionLevel: .none)
        let outDir = try signedDirectory()
        let outName = "\(appName)-signed.ipa"
        let outURL = outDir.appendingPathComponent(outName)
        if fm.fileExists(atPath: outURL.path) {
            try fm.removeItem(at: outURL)
        }
        try fm.moveItem(at: signedTemp, to: outURL)

        progressText = "Signed successfully."
        return outURL
    }

    /// Best-effort install: TrollStore URL scheme if available, else share sheet path returned for UI.
    func installURLSchemes(for signedIPA: URL) -> [URL] {
        var schemes: [URL] = []
        // TrollStore
        if let encoded = signedIPA.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let ts = URL(string: "apple-magnifier://install?url=\(encoded)") {
            schemes.append(ts)
        }
        return schemes
    }

    // MARK: - Session / cert

    private func loadAuthSession() throws -> AuthSession {
        guard let data = try KeychainVault.load(account: "sidesign-auth-session"),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data),
              session.session.isValid else {
            throw SignError.notSignedIn
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

    // MARK: - Device

    private func ensureDevice(team: Team, session: Session) async throws -> Device {
        let udid = deviceUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !udid.isEmpty else { throw SignError.missingUDID }

        let devices = try await portal.fetchDevices(for: team, types: .all, session: session)
        if let existing = devices.first(where: {
            $0.identifier.caseInsensitiveCompare(udid) == .orderedSame
        }) {
            return existing
        }

        let name = UIDevice.current.name
        do {
            return try await portal.registerDevice(
                name: name,
                identifier: udid,
                type: .iPhone,
                team: team,
                session: session
            )
        } catch {
            // Already registered under another name — re-fetch
            let again = try await portal.fetchDevices(for: team, types: .all, session: session)
            if let existing = again.first(where: {
                $0.identifier.caseInsensitiveCompare(udid) == .orderedSame
            }) {
                return existing
            }
            throw error
        }
    }

    // MARK: - App ID

    private func ensureAppID(name: String, bundleID: String, team: Team, session: Session) async throws -> AppID {
        let existing = try await portal.fetchAppIDs(for: team, session: session)
        if let found = existing.first(where: { $0.bundleIdentifier == bundleID }) {
            return found
        }
        // Free accounts: use a unique name
        let safeName = String(name.prefix(30))
        return try await portal.addAppID(withName: safeName, bundleIdentifier: bundleID, team: team, session: session)
    }

    // MARK: - Profile

    private func ensureProfile(
        appID: AppID,
        keyStore: KeyStore,
        device: Device,
        team: Team,
        session: Session
    ) async throws -> ProvisioningProfile {
        // Prefer Xcode-style team profile download (works for free + paid).
        do {
            return try await portal.downloadProvisioningProfile(
                for: appID,
                isTeamProfile: true,
                deviceType: .iPhone,
                team: team,
                session: session
            )
        } catch {
            // Fallback: create a manual development profile
            let certID = keyStore.certificate.identifier
                ?? UserDefaults.standard.string(forKey: Keys.certID)
                ?? keyStore.certificate.serialNumber

            let deviceID = device.deviceID ?? device.identifier

            return try await portal.createProvisioningProfile(
                name: "PurpleKit \(appID.bundleIdentifier)",
                appID: appID,
                certificateIDs: [certID],
                deviceIDs: [deviceID],
                team: team,
                session: session
            )
        }
    }

    // MARK: - Helpers

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

    static func saveCertificatePortalID(_ id: String?) {
        if let id, !id.isEmpty {
            UserDefaults.standard.set(id, forKey: Keys.certID)
        }
    }

    enum SignError: LocalizedError {
        case notSignedIn
        case noCertificate
        case noTeam
        case missingUDID
        case missingBundleID

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in with Apple ID first (Settings)."
            case .noCertificate:
                return "No development certificate in Keychain. Request one after sign-in."
            case .noTeam:
                return "No developer team on this Apple ID."
            case .missingUDID:
                return "Set your device UDID in Settings → Device UDID (Finder / Xcode / SideStore)."
            case .missingBundleID:
                return "Could not read CFBundleIdentifier from the app."
            }
        }
    }
}
