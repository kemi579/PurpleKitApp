import SwiftUI
import Network

struct PortCheckerTool: Tool {
    let id = "port"
    let name = "Port Checker"
    let icon = "network"
    let category: ToolCategory = .network
    let description = "Check if port is open"

    var content: AnyView { AnyView(PortCheckerView()) }
}

struct PortCheckerView: View {
    @State private var host = ""
    @State private var port = "80"
    @State private var status = ""
    @State private var loading = false

    var body: some View {
        ToolLayout(primaryTitle: loading ? "Проверка…" : "Проверить порт", isBusy: loading, primaryAction: check) {
            SettingsGroup {
                InputField(placeholder: "Хост", text: $host)
                SettingsDivider()
                InputField(placeholder: "Порт", text: $port)
            }
            if loading { ProgressView("Проверка соединения…") }
            if !status.isEmpty { ResultGroup(title: "Статус", value: status) }
        }
    }

    private func check() {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, let p = UInt16(port) else {
            status = "Invalid input"
            return
        }
        loading = true
        status = ""
        let connection = NWConnection(host: NWEndpoint.Host(h), port: NWEndpoint.Port(rawValue: p)!, using: .tcp)
        connection.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    status = "Open ✅"
                    loading = false
                    connection.cancel()
                    Haptic.success()
                case .failed, .cancelled:
                    if loading {
                        status = "Closed / Filtered ❌"
                        loading = false
                        Haptic.error()
                    }
                    connection.cancel()
                default:
                    break
                }
            }
        }
        connection.start(queue: .global())
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if loading {
                status = "Timeout / Closed ❌"
                loading = false
                connection.cancel()
                Haptic.error()
            }
        }
    }
}
