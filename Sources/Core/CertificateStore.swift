import Foundation
import SwiftUI

/// Local Apple ID + cert status storage.
/// Real free-cert signing still happens via AltStore/SideStore/Sideloadly —
/// we only keep credentials & status UI here (no private Apple APIs).
final class CertificateStore: ObservableObject {
    static let shared = CertificateStore()

    @Published var appleID: String = "" {
        didSet { UserDefaults.standard.set(appleID, forKey: Keys.appleID) }
    }
    @Published var isLoggedIn: Bool = false {
        didSet { UserDefaults.standard.set(isLoggedIn, forKey: Keys.loggedIn) }
    }
    @Published var certName: String = "" {
        didSet { UserDefaults.standard.set(certName, forKey: Keys.certName) }
    }
    @Published var certExpires: Date? {
        didSet {
            if let d = certExpires {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Keys.certExpires)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.certExpires)
            }
        }
    }
    @Published var lastRefresh: Date? {
        didSet {
            if let d = lastRefresh {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Keys.lastRefresh)
            }
        }
    }

    private enum Keys {
        static let appleID = "PurpleKit.appleID"
        static let loggedIn = "PurpleKit.loggedIn"
        static let certName = "PurpleKit.certName"
        static let certExpires = "PurpleKit.certExpires"
        static let lastRefresh = "PurpleKit.lastRefresh"
    }

    private init() {
        appleID = UserDefaults.standard.string(forKey: Keys.appleID) ?? ""
        isLoggedIn = UserDefaults.standard.bool(forKey: Keys.loggedIn)
        certName = UserDefaults.standard.string(forKey: Keys.certName) ?? ""
        let exp = UserDefaults.standard.double(forKey: Keys.certExpires)
        if exp > 0 { certExpires = Date(timeIntervalSince1970: exp) }
        let lr = UserDefaults.standard.double(forKey: Keys.lastRefresh)
        if lr > 0 { lastRefresh = Date(timeIntervalSince1970: lr) }
    }

    var daysLeft: Int? {
        guard let exp = certExpires else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0)
    }

    var certStatusText: String {
        guard isLoggedIn else { return "Not connected" }
        if let days = daysLeft {
            if days <= 0 { return "Expired — refresh needed" }
            if days <= 2 { return "Expires in \(days)d — refresh soon" }
            return "Active · \(days) days left"
        }
        return "Connected"
    }

    var isCertHealthy: Bool {
        guard isLoggedIn, let days = daysLeft else { return false }
        return days > 0
    }

    func login(email: String) {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return }
        appleID = e
        isLoggedIn = true
        // Free Apple ID cert is ~7 days. Placeholder until real pairing is added.
        certName = "iPhone Developer: \(e)"
        certExpires = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        lastRefresh = Date()
        Haptic.success()
    }

    func refreshCert() {
        guard isLoggedIn else { return }
        certExpires = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        lastRefresh = Date()
        Haptic.success()
    }

    func logout() {
        isLoggedIn = false
        certName = ""
        certExpires = nil
        lastRefresh = nil
        // keep appleID for convenience
        Haptic.light()
    }
}
