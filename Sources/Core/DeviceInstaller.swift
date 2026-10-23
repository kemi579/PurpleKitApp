import Foundation
import UIKit
import Minimuxer
import SideSign

/// On-device install pipeline modeled after SideStore:
/// 1) sign IPA (SideSign)
/// 2) start minimuxer with pairing file + local VPN
/// 3) send IPA over AFC
/// 4) install via InstallationProxy (`installIpa`)
///
/// Pairing file CANNOT be generated purely "from the phone body" inside a sandboxed app.
/// Apple stores lockdown pairing secrets outside the app sandbox. Same limitation as SideStore:
/// you need a one-time host pair (PC/Mac via iloader/Jitterbug/SideStore) OR a wireless-pair
/// session that writes a pairing file into Documents.
@MainActor
final class DeviceInstaller: ObservableObject {
    static let shared = DeviceInstaller()

    @Published private(set) var isWorking = false
    @Published private(set) var status = ""
    @Published private(set) var hasPairingFile = false
    @Published private(set) var isMuxerReady = false
    @Published private(set) var deviceUDIDFromMuxer: String?

    private let signer = IPASigningService.shared
    private let fm = FileManager.default

    private static let pairingFileName = "PurpleKit.mobiledevicepairing"

    private init() {
        refreshPairingState()
        // Best-effort: if user already has SideStore pairing in the app group / Files copy path, ignore.
        // Sandbox cannot read SideStore's container. Only our Documents.
    }

    func refreshPairingState() {
        if let url = try? pairingFileURL(), fm.fileExists(atPath: url.path) {
            hasPairingFile = true
        } else {
            hasPairingFile = false
        }
    }

    // MARK: - Pairing file

    func pairingFileURL() throws -> URL {
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent(Self.pairingFileName)
    }

    /// Import a pairing file exported by SideStore / Jitterbug / idevicepair / iloader.
    func importPairingFile(from source: URL) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let dest = try pairingFileURL()
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
        hasPairingFile = true
        status = "Pairing file saved."
    }

    func clearPairingFile() throws {
        let dest = try pairingFileURL()
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        hasPairingFile = false
        isMuxerReady = false
        deviceUDIDFromMuxer = nil
        status = "Pairing file removed."
    }

    // MARK: - Minimuxer lifecycle

    func startMuxer() async throws {
        status = "Starting minimuxer…"
        let pairing = try pairingFileURL()
        guard fm.fileExists(atPath: pairing.path) else {
            throw InstallError.missingPairingFile
        }

        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let mountPath = docs.appendingPathComponent("DDI", isDirectory: true)
        try fm.createDirectory(at: mountPath, withIntermediateDirectories: true)

        _ = await Minimuxer.shared.network.start()

        try await Minimuxer.shared.core.start(
            pairingFile: pairing.path,
            mountPath: mountPath.path,
            preferred: nil
        )

        let ready = await Minimuxer.shared.core.isReady(withNetworkCheck: true, withDDIMountCheck: false)
        switch ready {
        case .success(true):
            isMuxerReady = true
            if let udid = try? await Minimuxer.shared.core.fetchUDID() {
                deviceUDIDFromMuxer = udid
                if signer.deviceUDID.isEmpty {
                    signer.deviceUDID = udid
                }
            }
            status = "Minimuxer ready."
        case .success(false):
            isMuxerReady = false
            status = "Minimuxer started but device not reachable. Turn on LocalDevVPN / StosVPN."
            throw InstallError.deviceNotReachable
        case .failure(let err):
            isMuxerReady = false
            status = Minimuxer.shared.core.describeError(err)
            throw InstallError.muxerFailed(Minimuxer.shared.core.describeError(err))
        }
    }

    // MARK: - Sign + install

    func signAndInstall(ipaURL: URL) async throws {
        isWorking = true
        defer { isWorking = false }

        status = "Signing IPA…"
        let signed = try await signer.sign(ipaURL: ipaURL)

        status = "Preparing minimuxer…"
        if !isMuxerReady {
            try await startMuxer()
        } else {
            let ready = await Minimuxer.shared.core.isReady(withNetworkCheck: true, withDDIMountCheck: false)
            if case .success(true) = ready {
                // ok
            } else {
                try await startMuxer()
            }
        }

        status = "Reading signed IPA…"
        let ipaData = try Data(contentsOf: signed)
        let bundleID = try readBundleID(fromSignedIPA: signed)

        status = "Sending IPA over AFC…"
        try await Minimuxer.shared.core.sendIpaAfc(bundleId: bundleID, ipaBytes: ipaData)

        status = "Installing \(bundleID)…"
        try await Minimuxer.shared.core.installIpa(bundleId: bundleID)

        status = "Installed \(bundleID). Check Home Screen."
    }

    func installSigned(ipaURL: URL, bundleID: String) async throws {
        isWorking = true
        defer { isWorking = false }

        if !isMuxerReady {
            try await startMuxer()
        }

        status = "Sending IPA over AFC…"
        let data = try Data(contentsOf: ipaURL)
        try await Minimuxer.shared.core.sendIpaAfc(bundleId: bundleID, ipaBytes: data)

        status = "Installing…"
        try await Minimuxer.shared.core.installIpa(bundleId: bundleID)
        status = "Installed \(bundleID)."
    }

    private func readBundleID(fromSignedIPA ipaURL: URL) throws -> String {
        let work = fm.temporaryDirectory.appendingPathComponent("pk-bid-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let app = try fm.unzipAppBundle(at: ipaURL, to: work)
        let info = app.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: info) as? [String: Any],
              let bid = dict["CFBundleIdentifier"] as? String else {
            throw InstallError.missingBundleID
        }
        return bid
    }

    enum InstallError: LocalizedError {
        case missingPairingFile
        case deviceNotReachable
        case muxerFailed(String)
        case missingBundleID

        var errorDescription: String? {
            switch self {
            case .missingPairingFile:
                return "Pairing file is not on the phone for apps to read. Import .mobiledevicepairing once from PC (iloader / SideStore / Jitterbug) — same as SideStore. Cannot auto-take it from the device sandbox."
            case .deviceNotReachable:
                return "Device not reachable via minimuxer. Connect LocalDevVPN or StosVPN."
            case .muxerFailed(let msg):
                return "Minimuxer: \(msg)"
            case .missingBundleID:
                return "Could not read CFBundleIdentifier from signed IPA."
            }
        }
    }
}
