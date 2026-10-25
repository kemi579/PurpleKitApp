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
        ToolLayout {
            SettingsGroup {
                Picker("Режим", selection: $mode) {
                    Text("Encode").tag(0)
                    Text("Decode").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(Theme.rowInset)
                .onChange(of: mode) { _ in process() }
                SettingsDivider()
                InputField(placeholder: mode == 0 ? "Текст для кодирования" : "Base64 для декодирования",
                           text: $input, isMultiline: true)
                    .onChange(of: input) { _ in process() }
            }
            if let error { Text(error).font(.subheadline).foregroundStyle(Theme.error) }
            ResultGroup(title: "Результат", value: output)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                IconAction(title: "Очистить", icon: "trash") {
                    input = ""; output = ""; error = nil
                }
            }
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
