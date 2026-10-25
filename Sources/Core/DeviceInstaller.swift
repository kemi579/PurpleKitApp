import Foundation
import UIKit
import Minimuxer
import SideSign

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
    private var isStarting = false
    private var hasStartedCore = false
    private static let pairingFileName = "PurpleKit.mobiledevicepairing"

    private init() { refreshPairingState() }

    func refreshPairingState() {
        hasPairingFile = (try? pairingFileURL()).map { fm.fileExists(atPath: $0.path) } ?? false
    }

    func pairingFileURL() throws -> URL {
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent(Self.pairingFileName)
    }

    func importPairingFile(from source: URL) throws {
        guard !isWorking && !isStarting && !signer.isWorking else { throw InstallError.busy }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0, size <= 1_048_576 else {
            throw InstallError.invalidPairingFile
        }
        let data = try Data(contentsOf: source)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let host = plist["HostID"] as? String, !host.isEmpty,
              let system = plist["SystemBUID"] as? String, !system.isEmpty,
              plist["HostPrivateKey"] is Data,
              plist["HostCertificate"] is Data else {
            throw InstallError.invalidPairingFile
        }
        let destination = try pairingFileURL()
        // Validate before replacing the previous pairing record. Atomic write preserves it on failure.
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var protectedURL = destination
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try protectedURL.setResourceValues(resourceValues)
        hasPairingFile = true
        isMuxerReady = false
        deviceUDIDFromMuxer = nil
        signer.deviceUDID = ""
        status = "Pairing сохранён. Включи локальный VPN перед установкой."
    }

    func clearPairingFile() throws {
        guard !isWorking && !isStarting && !signer.isWorking else { throw InstallError.busy }
        let destination = try pairingFileURL()
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        hasPairingFile = false
        isMuxerReady = false
        deviceUDIDFromMuxer = nil
        signer.deviceUDID = ""
        status = "Pairing удалён."
    }

    func startMuxer() async throws {
        guard !isWorking && !isStarting && !signer.isWorking else { throw InstallError.busy }
        isWorking = true
        defer { isWorking = false }
        try await connectMuxer()
    }

    private func connectMuxer() async throws {
        guard !isStarting else { throw InstallError.busy }
        isStarting = true
        isMuxerReady = false
        deviceUDIDFromMuxer = nil
        defer { isStarting = false }
        status = "Подключение к устройству…"

        do {
            let pairing = try pairingFileURL()
            guard fm.fileExists(atPath: pairing.path) else { throw InstallError.missingPairingFile }
            if hasStartedCore {
                try await Minimuxer.shared.core.stop()
                hasStartedCore = false
            }
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let mountPath = docs.appendingPathComponent("DDI", isDirectory: true)
            try fm.createDirectory(at: mountPath, withIntermediateDirectories: true)
            _ = await Minimuxer.shared.network.start()
            try await Minimuxer.shared.core.start(pairingFile: pairing.path, mountPath: mountPath.path, preferred: nil)
            hasStartedCore = true

            // Allow network discovery to settle instead of failing on the first readiness probe.
            for attempt in 0..<12 {
                try Task.checkCancellation()
                let ready = await Minimuxer.shared.core.isReady(withNetworkCheck: true, withDDIMountCheck: false)
                switch ready {
                case .success(true):
                    let udid = try await Minimuxer.shared.core.fetchUDID()
                    guard SideloadValidation.isValidUDID(udid) else { throw InstallError.invalidUDID }
                    deviceUDIDFromMuxer = udid
                    signer.deviceUDID = udid
                    isMuxerReady = true
                    status = "Устройство подключено."
                    return
                case .success(false):
                    if attempt == 11 { throw InstallError.deviceNotReachable }
                case .failure(let error):
                    throw InstallError.muxerFailed(Minimuxer.shared.core.describeError(error))
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        } catch {
            isMuxerReady = false
            deviceUDIDFromMuxer = nil
            status = error.localizedDescription
            throw error
        }
    }

    private func prepareDevice() async throws {
        if isMuxerReady {
            let ready = await Minimuxer.shared.core.isReady(withNetworkCheck: true, withDDIMountCheck: false)
            if case .success(true) = ready {
                let udid = try await Minimuxer.shared.core.fetchUDID()
                guard SideloadValidation.isValidUDID(udid) else { throw InstallError.invalidUDID }
                deviceUDIDFromMuxer = udid
                signer.deviceUDID = udid
                return
            }
        }
        try await connectMuxer()
    }

    func signAndInstall(ipaURL: URL) async throws {
        guard !isWorking && !isStarting && !signer.isWorking else { throw InstallError.busy }
        isWorking = true
        defer { isWorking = false }

        do {
            // Local preflight avoids expensive setup when the account is missing.
            try signer.validateCredentials()
            // Pair and fetch the actual UDID BEFORE provisioning/signing.
            try await prepareDevice()
            status = "Подпись IPA…"
            let signed = try await signer.sign(ipaURL: ipaURL)
            try Task.checkCancellation()
            // The connection may have changed while Apple was issuing profiles.
            let signedForUDID = signer.deviceUDID
            try await prepareDevice()
            guard signer.deviceUDID.caseInsensitiveCompare(signedForUDID) == .orderedSame else {
                throw InstallError.deviceChanged
            }
            try await transferAndInstall(ipaURL: signed, expectedBundleID: nil)
        } catch {
            status = "Установка не завершена: \(error.localizedDescription)"
            throw error
        }
    }

    /// Installs an already signed IPA without issuing a new certificate or profile.
    func installSigned(ipaURL: URL, bundleID: String) async throws {
        guard !isWorking && !isStarting && !signer.isWorking else { throw InstallError.busy }
        isWorking = true
        defer { isWorking = false }
        do {
            try await prepareDevice()
            try await transferAndInstall(ipaURL: ipaURL, expectedBundleID: bundleID)
        } catch {
            status = "Установка не завершена: \(error.localizedDescription)"
            throw error
        }
    }

    private func transferAndInstall(ipaURL: URL, expectedBundleID: String?) async throws {
        status = "Проверка подписанного IPA…"
        let udid = signer.deviceUDID
        let package = try await Task.detached(priority: .userInitiated) {
            try Self.readSignedPackage(at: ipaURL, deviceUDID: udid)
        }.value
        if let expectedBundleID, expectedBundleID != package.bundleID {
            throw InstallError.bundleMismatch
        }
        try Task.checkCancellation()
        status = "Передача IPA на устройство…"
        do {
            try await Minimuxer.shared.core.sendIpaAfc(bundleId: package.bundleID, ipaBytes: package.data)
            try Task.checkCancellation()
            status = "Установка \(package.bundleID)…"
            // Only report success after InstallationProxy completes.
            try await Minimuxer.shared.core.installIpa(bundleId: package.bundleID)
        } catch {
            isMuxerReady = false
            throw error
        }
        status = "Установлено: \(package.bundleID). Проверь экран «Домой»."
    }

    private nonisolated static func readSignedPackage(at url: URL, deviceUDID: String) throws -> (bundleID: String, data: Data) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("pk-install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let appURL = try fm.unzipAppBundle(at: url, to: work)
        guard let app = AppBundle(fileURL: appURL) else { throw InstallError.missingBundleID }
        for bundle in app.allAppBundles {
            guard let profile = bundle.provisioningProfile,
                  profile.bundleIdentifier == bundle.bundleIdentifier,
                  profile.expirationDate > Date(),
                  profile.deviceIDs.contains(where: { $0.caseInsensitiveCompare(deviceUDID) == .orderedSame }) else {
                throw InstallError.invalidSignedProfile
            }
        }
        return (app.bundleIdentifier, try Data(contentsOf: url))
    }

    enum InstallError: LocalizedError {
        case busy, missingPairingFile, invalidPairingFile, invalidUDID, deviceNotReachable
        case muxerFailed(String)
        case missingBundleID, bundleMismatch, invalidSignedProfile, deviceChanged

        var errorDescription: String? {
            switch self {
            case .busy: return "Другая операция уже выполняется. Дождись её завершения."
            case .missingPairingFile:
                return "Импортируй pairing-файл в настройках. Его нужно один раз получить на PC/Mac через совместимый инструмент pairing."
            case .invalidPairingFile:
                return "Это не корректный pairing-файл. Выбери исходный .mobiledevicepairing, экспортированный для этого iPhone."
            case .invalidUDID: return "Устройство вернуло некорректный UDID. Проверь pairing."
            case .deviceNotReachable:
                return "iPhone недоступен. Включи совместимый локальный VPN и проверь pairing-файл."
            case .muxerFailed(let message): return "Ошибка подключения: \(message)"
            case .missingBundleID: return "Не удалось прочитать приложение внутри подписанного IPA."
            case .bundleMismatch: return "Bundle ID подписанного IPA не совпадает с выбранным приложением."
            case .invalidSignedProfile: return "Профиль IPA истёк или не подходит этому устройству. Подпиши файл заново."
            case .deviceChanged: return "Подключённое устройство изменилось во время подписи. Повтори установку."
            }
        }
    }
}
