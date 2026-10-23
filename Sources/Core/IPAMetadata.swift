import Foundation
import UIKit
import SideSign

/// Reads display name / version / bundle id / icon from an IPA (cached).
enum IPAMetadata {
    struct Info: Sendable {
        var displayName: String
        var version: String?
        var bundleID: String?
        var iconPath: String? // absolute path in IconCache
    }

    private static let cacheFolder = "IconCache"

    static func load(ipaURL: URL) -> Info {
        let stem = ipaURL.deletingPathExtension().lastPathComponent
        var info = Info(displayName: stem, version: nil, bundleID: nil, iconPath: nil)

        let fm = FileManager.default
        let work: URL
        do {
            work = fm.temporaryDirectory.appendingPathComponent("pk-meta-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            return info
        }
        defer { try? fm.removeItem(at: work) }

        do {
            let app = try fm.unzipAppBundle(at: ipaURL, to: work)
            let plistURL = app.appendingPathComponent("Info.plist")
            guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return info }

            if let name = dict["CFBundleDisplayName"] as? String, !name.isEmpty {
                info.displayName = name
            } else if let name = dict["CFBundleName"] as? String, !name.isEmpty {
                info.displayName = name
            }
            info.version = dict["CFBundleShortVersionString"] as? String
            info.bundleID = dict["CFBundleIdentifier"] as? String

            if let icon = extractIcon(from: app, infoPlist: dict) {
                if let cached = cacheIcon(icon, key: ipaURL.lastPathComponent) {
                    info.iconPath = cached.path
                }
            }
        } catch {
            return info
        }
        return info
    }

    private static func extractIcon(from app: URL, infoPlist: [String: Any]) -> UIImage? {
        let fm = FileManager.default
        var candidates: [String] = []

        // Primary icon from Info.plist
        if let icons = infoPlist["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }
        if let icons = infoPlist["CFBundleIcons~ipad"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }
        if let files = infoPlist["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }
        if let single = infoPlist["CFBundleIconFile"] as? String {
            candidates.append(single)
        }
        // Common fallbacks
        candidates.append(contentsOf: [
            "AppIcon60x60@2x", "AppIcon60x60@3x", "AppIcon",
            "Icon-60@2x", "Icon-60@3x", "Icon@2x", "Icon",
            "AppIcon76x76@2x~ipad", "iTunesArtwork@2x", "iTunesArtwork"
        ])

        let suffixes = ["", ".png", "@2x.png", "@3x.png", "~ipad.png", "@2x~ipad.png"]

        for name in candidates {
            let base = name.replacingOccurrences(of: ".png", with: "")
            for suffix in suffixes {
                let path = app.appendingPathComponent(base + suffix)
                if fm.fileExists(atPath: path.path),
                   let img = UIImage(contentsOfFile: path.path) {
                    return img
                }
            }
        }

        // Scan for largest PNG that looks like an icon
        if let enumerator = fm.enumerator(at: app, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            var best: (URL, Int64)?
            for case let url as URL in enumerator {
                let n = url.lastPathComponent.lowercased()
                guard n.hasSuffix(".png"),
                      (n.contains("appicon") || n.contains("icon") || n.hasPrefix("icon")) else { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                if best == nil || size > best!.1 { best = (url, size) }
            }
            if let best, let img = UIImage(contentsOfFile: best.0.path) {
                return img
            }
        }
        return nil
    }

    private static func cacheIcon(_ image: UIImage, key: String) -> URL? {
        guard let data = image.pngData() else { return nil }
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent(cacheFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safe = key.replacingOccurrences(of: "/", with: "_")
            let url = dir.appendingPathComponent("\(safe).png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func cachedIcon(for ipaURL: URL) -> UIImage? {
        let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let safe = ipaURL.lastPathComponent.replacingOccurrences(of: "/", with: "_")
        guard let path = docs?.appendingPathComponent(cacheFolder).appendingPathComponent("\(safe).png").path,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
