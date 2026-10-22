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
        ScrollView {
            VStack(spacing: 12) {
                infoRow("Model", UIDevice.current.model)
                infoRow("Name", UIDevice.current.name)
                infoRow("System", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                infoRow("Identifier", machineName())
                infoRow("Battery", String(format: "%.0f%% (%@)", batteryLevel * 100, batteryState))
                infoRow("Memory Total", formatBytes(ProcessInfo.processInfo.physicalMemory))
                infoRow("Disk Total", formatBytes(diskSpace().total))
                infoRow("Disk Free", formatBytes(diskSpace().free))
                infoRow("Uptime", formatUptime(ProcessInfo.processInfo.systemUptime))
                infoRow("Processors", "\(ProcessInfo.processInfo.processorCount)")
            }
            .padding()
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
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(Theme.textPrimary)
                .font(.system(size: 14, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
