import SwiftUI

struct MyIPTool: Tool {
    let id = "myip"
    let name = "My IP"
    let icon = "globe"
    let category: ToolCategory = .network
    let description = "Public IP address"

    var content: AnyView { AnyView(MyIPView()) }
}

struct MyIPView: View {
    @State private var ip = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ToolLayout(primaryTitle: loading ? "Обновление…" : "Обновить", isBusy: loading, primaryAction: fetch) {
            if loading { ProgressView("Получение IP…") }
            ResultGroup(title: "Публичный IP", value: ip)
            if let error { Text(error).font(.subheadline).foregroundStyle(Theme.error) }
        }
        .onAppear { fetch() }
    }

    private func fetch() {
        loading = true
        error = nil
        guard let url = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                loading = false
                if let err = err {
                    error = err.localizedDescription
                    return
                }
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    ip = str
                    Haptic.success()
                }
            }
        }.resume()
    }
}
