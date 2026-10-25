import SwiftUI

struct JSONFormatterTool: Tool {
    let id = "json"
    let name = "JSON Formatter"
    let icon = "curlybraces"
    let category: ToolCategory = .text
    let description = "Pretty-print & minify JSON"

    var content: AnyView { AnyView(JSONFormatterView()) }
}

struct JSONFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?

    var body: some View {
        ToolLayout(primaryTitle: "Форматировать", primaryAction: { format(pretty: true) }) {
            SettingsGroup {
                InputField(placeholder: "JSON", text: $input, isMultiline: true)
            }
            if let error { Text(error).font(.subheadline).foregroundStyle(Theme.error) }
            ResultGroup(title: "Результат", value: output)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { format(pretty: false) } label: { Label("Сжать JSON", systemImage: "text.justify") }
                    Button {
                        UIPasteboard.general.string = output
                        Haptic.success()
                    } label: { Label("Копировать результат", systemImage: "doc.on.doc") }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Действия с JSON")
            }
        }
    }

    private func format(pretty: Bool) {
        error = nil
        guard let data = input.data(using: .utf8) else {
            error = "Invalid input"
            return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : []
            let out = try JSONSerialization.data(withJSONObject: obj, options: options)
            output = String(data: out, encoding: .utf8) ?? ""
            Haptic.success()
        } catch {
            self.error = "Invalid JSON"
            output = ""
            Haptic.error()
        }
    }
}
