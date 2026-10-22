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
        ScrollView {
            VStack(spacing: 16) {
                PurpleTextField(placeholder: "Paste JSON…", text: $input, isMultiline: true)

                HStack(spacing: 12) {
                    PurpleButton(title: "Pretty", icon: "text.alignleft") {
                        format(pretty: true)
                    }
                    PurpleButton(title: "Minify", icon: "text.justify", style: .secondary) {
                        format(pretty: false)
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.error)
                }

                ResultBox(title: "Result", value: output) {}

                PurpleButton(title: "Copy Result", icon: "doc.on.doc") {
                    UIPasteboard.general.string = output
                    Haptic.success()
                }
            }
            .padding()
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
