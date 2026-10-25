import SwiftUI

struct URLEncodeTool: Tool {
    let id = "urlencode"
    let name = "URL Encode"
    let icon = "link"
    let category: ToolCategory = .text
    let description = "URL encode & decode"

    var content: AnyView { AnyView(URLEncodeView()) }
}

struct URLEncodeView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var mode = 0

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
                InputField(placeholder: "Текст или URL", text: $input, isMultiline: true)
                    .onChange(of: input) { _ in process() }
            }
            ResultGroup(title: "Результат", value: output)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                IconAction(title: "Очистить", icon: "trash") { input = ""; output = "" }
            }
        }
    }

    private func process() {
        guard !input.isEmpty else { output = ""; return }
        if mode == 0 {
            output = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        } else {
            output = input.removingPercentEncoding ?? input
        }
    }
}
