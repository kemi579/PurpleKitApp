import Foundation
import SwiftUI
import SideSign

@MainActor
final class CertificateStore: ObservableObject {
    static let shared = CertificateStore()

    @Published var appleID: String = "" {
        didSet { UserDefaults.standard.set(appleID, forKey: Keys.appleID) }
    }
    @Published private(set) var isLoggedIn = false
    @Published private(set) var certName = ""
    @Published private(set) var certExpires: Date?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var teamName = ""

    private enum Keys {
        static let appleID = "PurpleKit.appleID"
        static let loggedIn = "PurpleKit.loggedIn"
        static let certName = "PurpleKit.certName"
        static let certExpires = "PurpleKit.certExpires"
        static let lastRefresh = "PurpleKit.lastRefresh"
        static let teamName = "PurpleKit.teamName"
    }

    private init() {
        appleID = UserDefaults.standard.string(forKey: Keys.appleID) ?? ""
        if let sessionData = try? KeychainVault.load(account: "sidesign-auth-session"),
           let session = try? JSONDecoder().decode(AuthSession.self, from: sessionData),
           session.session.isValid {
            appleID = session.account.appleID
            isLoggedIn = true
            teamName = UserDefaults.standard.string(forKey: Keys.teamName) ?? ""
            if let p12 = try? KeychainVault.load(account: "sidesign-development-certificate-p12"),
               let passwordData = try? KeychainVault.load(account: "sidesign-development-certificate-password"),
               let password = String(data: passwordData, encoding: .utf8),
               let keys = try? KeyStore(p12Data: p12, password: password) {
                certName = keys.certificate.name
                certExpires = keys.certificate.expiryDate
            }
        }
    }

    var daysLeft: Int? {
        guard let exp = certExpires else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0)
    }

    var certStatusText: String {
        if !isLoggedIn {
            return "Not signed in"
        }
        if let days = daysLeft, !certName.isEmpty {
            return days > 0 ? "Cert · \(days)d left" : "Cert expired"
        }
        if isLoggedIn && certName.isEmpty {
            return "Signed in · no cert yet"
        }
        return "Signed in"
    }

    var isCertHealthy: Bool {
        guard isLoggedIn, !certName.isEmpty, let days = daysLeft else { return false }
        return days > 1
    }

    /// Called after a real SideSign authentication succeeds.
    func applyAuthenticatedSession(email: String, team: String?) {
        appleID = email
        isLoggedIn = true
        teamName = team ?? ""
        UserDefaults.standard.set(true, forKey: Keys.loggedIn)
        UserDefaults.standard.set(teamName, forKey: Keys.teamName)
        Haptic.success()
    }

    /// Called after a development certificate is issued and stored in Keychain.
    func applyCertificate(name: String, expires: Date?) {
        certName = name
        certExpires = expires
        lastRefresh = Date()
        UserDefaults.standard.set(name, forKey: Keys.certName)
        if let expires {
            UserDefaults.standard.set(expires.timeIntervalSince1970, forKey: Keys.certExpires)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastRefresh)
        Haptic.success()
    }

    func logout() {
        isLoggedIn = false
        certName = ""
        certExpires = nil
        lastRefresh = nil
        teamName = ""
        UserDefaults.standard.set(false, forKey: Keys.loggedIn)
        UserDefaults.standard.removeObject(forKey: Keys.certName)
        UserDefaults.standard.removeObject(forKey: Keys.certExpires)
        UserDefaults.standard.removeObject(forKey: Keys.lastRefresh)
        UserDefaults.standard.removeObject(forKey: Keys.teamName)
        Haptic.light()
    }

    /// No-op placeholder; real refresh is done via SideSign on the sign-in screen.
    func refreshCert() {
        Haptic.light()
    }
}
