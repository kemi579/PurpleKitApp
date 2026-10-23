import Foundation
import SwiftUI

/// Stores only the user's Apple ID email and genuine status values.
/// Authentication, certificate creation and certificate refresh are intentionally
/// unavailable until the real SideSign flow is integrated.
final class CertificateStore: ObservableObject {
    static let shared = CertificateStore()

    @Published var appleID: String = "" {
        didSet { UserDefaults.standard.set(appleID, forKey: Keys.appleID) }
    }
    @Published private(set) var isLoggedIn = false
    @Published private(set) var certName = ""
    @Published private(set) var certExpires: Date?
    @Published private(set) var lastRefresh: Date?

    private enum Keys {
        static let appleID = "PurpleKit.appleID"
        static let loggedIn = "PurpleKit.loggedIn"
        static let certName = "PurpleKit.certName"
        static let certExpires = "PurpleKit.certExpires"
        static let lastRefresh = "PurpleKit.lastRefresh"
    }

    private init() {
        appleID = UserDefaults.standard.string(forKey: Keys.appleID) ?? ""

        // Remove legacy placeholder state from older builds. Those values were
        // generated locally and did not represent an Apple-issued certificate.
        UserDefaults.standard.set(false, forKey: Keys.loggedIn)
        UserDefaults.standard.removeObject(forKey: Keys.certName)
        UserDefaults.standard.removeObject(forKey: Keys.certExpires)
        UserDefaults.standard.removeObject(forKey: Keys.lastRefresh)
    }

    var daysLeft: Int? {
        guard let exp = certExpires else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0)
    }

    var certStatusText: String {
        "Not authenticated — real Apple ID sign-in is not available yet"
    }

    var isCertHealthy: Bool { false }

    /// Saves the email as a convenience only. This does not sign in to Apple.
    func login(email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appleID = trimmed
        Haptic.light()
    }

    /// Deliberately does not extend expiry or claim a certificate was refreshed.
    func refreshCert() {
        Haptic.light()
    }

    func logout() {
        isLoggedIn = false
        certName = ""
        certExpires = nil
        lastRefresh = nil
        UserDefaults.standard.set(false, forKey: Keys.loggedIn)
        UserDefaults.standard.removeObject(forKey: Keys.certName)
        UserDefaults.standard.removeObject(forKey: Keys.certExpires)
        UserDefaults.standard.removeObject(forKey: Keys.lastRefresh)
        Haptic.light()
    }
}
