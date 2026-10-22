import SwiftUI

struct Base64Tool: Tool {
    let id = "base64"
    let name = "Base64"
    let icon = "textformat.abc"
    let category: ToolCategory = .text
    let description = "Encode & decode Base64"

    var content: AnyView {
        AnyView(Base64View())
    }
}

struct Base64View: View {
    @State private var input = ""
    @State private var output = ""
    @State private var mode = 0
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    Text("Encode").tag(0)
                    Text("Decode").tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in process() }

                PurpleTextField(placeholder: mode == 0 ? "Text to encode…" : "Base64 to decode…", text: $input, isMultiline: true)
                    .onChange(of: input) { _ in process() }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.error)
                }

                ResultBox(title: "Result", value: output) {}

                HStack(spacing: 12) {
                    PurpleButton(title: "Copy", icon: "doc.on.doc") {
                        UIPasteboard.general.string = output
                        Haptic.success()
                    }
                    PurpleButton(title: "Clear", icon: "trash", style: .secondary) {
                        input = ""
                        output = ""
                        error = nil
                    }
                }
            }
            .padding()
        }
    }

    private func process() {
        error = nil
        guard !input.isEmpty else {
            output = ""
            return
        }
        if mode == 0 {
            output = Data(input.utf8).base64EncodedString()
        } else {
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                error = "Invalid Base64"
                output = ""
                return
            }
            output = String(data: data, encoding: .utf8) ?? "Unable to decode as UTF-8"
        }
    }
}
