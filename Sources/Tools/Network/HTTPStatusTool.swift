import SwiftUI

struct HTTPStatusTool: Tool {
    let id = "httpstatus"
    let name = "HTTP Status"
    let icon = "globe"
    let category: ToolCategory = .network
    let description = "Check HTTP response status"

    var content: AnyView { AnyView(HTTPStatusView()) }
}

struct HTTPStatusView: View {
    @State private var urlString = "https://"
    @State private var status = ""
    @State private var loading = false
    @State private var headers: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PurpleTextField(placeholder: "https://example.com", text: $urlString)

                PurpleButton(title: "Check", icon: "arrow.up.right") {
                    check()
                }

                if loading {
                    ProgressView().tint(Theme.primaryLight)
                }

                if !status.isEmpty {
                    ResultBox(title: "Status", value: status) {}
                }

                ForEach(headers, id: \.self) { h in
                    Text(h)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private func check() {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s) else {
            status = "Invalid URL"
            return
        }
        loading = true
        status = ""
        headers = []
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                loading = false
                if let error = error {
                    status = error.localizedDescription
                    Haptic.error()
                    return
                }
                if let http = response as? HTTPURLResponse {
                    status = "\(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
                    headers = http.allHeaderFields.map { "\($0.key): \($0.value)" }.sorted()
                    Haptic.success()
                }
            }
        }.resume()
    }
}
