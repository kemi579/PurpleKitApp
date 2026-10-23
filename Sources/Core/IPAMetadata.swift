import Foundation
import UIKit
import SideSign

/// Fast metadata for library rows. Full IPA unzip happens at most once per file
/// (keyed by path + size + mtime). Cache lives in Documents/MetaCache.
enum IPAMetadata {
    struct Info: Codable, Sendable {
        var displayName: String
        var version: String?
        var bundleID: String?
        var iconFileName: String? // relative name under IconCache
        var sourceSize: Int64
        var sourceMTime: Double

        var iconPath: String? {
            guard let iconFileName else { return nil }
            guard let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
            let path = docs.appendingPathComponent("IconCache").appendingPathComponent(iconFileName).path
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    private static let metaFolder = "MetaCache"
    private static let iconFolder = "IconCache"

    /// Instant path: cache hit → no unzip. Miss → unzip once, then cache.
    static func load(ipaURL: URL) -> Info {
        let stem = ipaURL.deletingPathExtension().lastPathComponent
        let values = try? ipaURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values?.fileSize ?? 0)
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

        if let cached = readCache(for: ipaURL), cached.sourceSize == size, cached.sourceMTime == mtime {
            return cached
        }

        var info = Info(
            displayName: stem,
            version: nil,
            bundleID: nil,
            iconFileName: nil,
            sourceSize: size,
            sourceMTime: mtime
        )

        // Slow path only when needed
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("pk-meta-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: work) }

            let app = try fm.unzipAppBundle(at: ipaURL, to: work)
            let plistURL = app.appendingPathComponent("Info.plist")
            guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
                writeCache(info, for: ipaURL)
                return info
            }

            if let name = dict["CFBundleDisplayName"] as? String, !name.isEmpty {
                info.displayName = name
            } else if let name = dict["CFBundleName"] as? String, !name.isEmpty {
                info.displayName = name
            }
            info.version = dict["CFBundleShortVersionString"] as? String
            info.bundleID = dict["CFBundleIdentifier"] as? String

            if let icon = extractIcon(from: app, infoPlist: dict),
               let name = cacheIcon(icon, key: ipaURL.lastPathComponent) {
                info.iconFileName = name
            }
            writeCache(info, for: ipaURL)
        } catch {
            // leave filename-only info
        }
        return info
    }

    /// Lightweight row for first paint (no unzip).
    static func placeholder(ipaURL: URL, size: Int64) -> Info {
        let values = try? ipaURL.resourceValues(forKeys: [.contentModificationDateKey])
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        if let cached = readCache(for: ipaURL), cached.sourceSize == size, cached.sourceMTime == mtime {
            return cached
        }
        return Info(
            displayName: ipaURL.deletingPathExtension().lastPathComponent,
            version: nil,
            bundleID: nil,
            iconFileName: nil,
            sourceSize: size,
            sourceMTime: mtime
        )
    }

    // MARK: - Disk cache

    private static func cacheKey(for ipaURL: URL) -> String {
        ipaURL.lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func metaURL(for ipaURL: URL) throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent(metaFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(cacheKey(for: ipaURL) + ".json")
    }

    private static func readCache(for ipaURL: URL) -> Info? {
        guard let url = try? metaURL(for: ipaURL),
              let data = try? Data(contentsOf: url),
              let info = try? JSONDecoder().decode(Info.self, from: data) else { return nil }
        return info
    }

    private static func writeCache(_ info: Info, for ipaURL: URL) {
        guard let url = try? metaURL(for: ipaURL),
              let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Icon

    private static func extractIcon(from app: URL, infoPlist: [String: Any]) -> UIImage? {
        let fm = FileManager.default
        var candidates: [String] = []

        if let icons = infoPlist["CFBundleIcons"] as? [String: Any],
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
        candidates.append(contentsOf: [
            "AppIcon60x60@2x", "AppIcon60x60@3x", "AppIcon",
            "Icon-60@2x", "Icon@2x", "Icon", "iTunesArtwork@2x"
        ])

        let suffixes = ["", ".png", "@2x.png", "@3x.png"]
        for name in candidates {
            let base = name.replacingOccurrences(of: ".png", with: "")
            for suffix in suffixes {
                let path = app.appendingPathComponent(base + suffix)
                if fm.fileExists(atPath: path.path), let img = UIImage(contentsOfFile: path.path) {
                    return img
                }
            }
        }
        return nil
    }

    private static func cacheIcon(_ image: UIImage, key: String) -> String? {
        // Downscale for list performance
        let target = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: target)
        let small = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = small.pngData() else { return nil }
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent(iconFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = cacheKey(for: URL(fileURLWithPath: key)) + ".png"
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}
