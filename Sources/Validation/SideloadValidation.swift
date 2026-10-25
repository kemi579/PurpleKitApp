import Foundation

/// Pure checks shared by the iOS app and the standalone Swift package tests.
public enum SideloadValidation {
    public static func isValidUDID(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if value.count == 40 {
            return value.unicodeScalars.allSatisfy { hex.contains($0) }
        }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0].count == 8 && parts[1].count == 16
            && parts.allSatisfy { $0.unicodeScalars.allSatisfy { hex.contains($0) } }
    }

    /// Uses a stable team-specific ID so updates target the same installed app.
    /// Changes apply only to the extracted signing workspace, never the imported IPA.
    public static func resignedBundleID(originalRoot: String, bundleID: String, teamID: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard !originalRoot.isEmpty, !teamID.isEmpty,
              bundleID == originalRoot || bundleID.hasPrefix(originalRoot + "."),
              (originalRoot + bundleID + teamID).unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        let suffix = ".purplekit." + teamID.lowercased()
        let root = originalRoot.hasSuffix(suffix) ? originalRoot : originalRoot + suffix
        let result = root + bundleID.dropFirst(originalRoot.count)
        return result.utf8.count <= 255 ? result : nil
    }

    public static func profileMatches(
        bundleID: String, teamID: String, udid: String, certificateSerial: String,
        profileBundleID: String, profileTeamID: String, profileDevices: [String],
        profileCertificateSerials: [String], expiration: Date, now: Date = Date()
    ) -> Bool {
        expiration > now
            && bundleID == profileBundleID
            && teamID == profileTeamID
            && profileDevices.contains { $0.caseInsensitiveCompare(udid) == .orderedSame }
            && profileCertificateSerials.contains {
                $0.caseInsensitiveCompare(certificateSerial) == .orderedSame
            }
    }
}
