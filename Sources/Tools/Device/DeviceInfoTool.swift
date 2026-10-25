import SwiftUI
import UIKit

struct DeviceInfoTool: Tool {
    let id = "device"
    let name = "Device Info"
    let icon = "iphone"
    let category: ToolCategory = .device
    let description = "Model, iOS, battery, memory"

    var content: AnyView { AnyView(DeviceInfoView()) }
}

struct DeviceInfoView: View {
    @State private var batteryLevel: Float = 0
    @State private var batteryState = ""

    var body: some View {
        ToolLayout {
            SettingsGroup {
                infoRow("Модель", UIDevice.current.model)
                SettingsDivider()
                infoRow("Имя", UIDevice.current.name)
                SettingsDivider()
                infoRow("Система", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                SettingsDivider()
                infoRow("Идентификатор", machineName())
            }
            SectionHeading(title: "Состояние")
            SettingsGroup {
                infoRow("Батарея", String(format: "%.0f%% (%@)", batteryLevel * 100, batteryState))
                SettingsDivider()
                infoRow("Память", formatBytes(ProcessInfo.processInfo.physicalMemory))
                SettingsDivider()
                infoRow("Диск", formatBytes(diskSpace().total))
                SettingsDivider()
                infoRow("Свободно", formatBytes(diskSpace().free))
                SettingsDivider()
                infoRow("Время работы", formatUptime(ProcessInfo.processInfo.systemUptime))
                SettingsDivider()
                infoRow("Процессоры", "\(ProcessInfo.processInfo.processorCount)")
            }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel
            switch UIDevice.current.batteryState {
            case .charging: batteryState = "Charging"
            case .full: batteryState = "Full"
            case .unplugged: batteryState = "Unplugged"
            default: batteryState = "Unknown"
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        SettingsRow(title: title, value: value, showsChevron: false)
    }

    private func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func diskSpace() -> (total: UInt64, free: UInt64) {
        let home = NSHomeDirectory() as NSString
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home as String),
              let total = attrs[.systemSize] as? UInt64,
              let free = attrs[.systemFreeSize] as? UInt64 else {
            return (0, 0)
        }
        return (total, free)
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return "\(h)h \(m)m"
    }
}
