import SwiftUI

struct CaseConverterTool: Tool {
    let id = "case"
    let name = "Case Converter"
    let icon = "textformat"
    let category: ToolCategory = .text
    let description = "UPPER, lower, Title, camel…"

    var content: AnyView { AnyView(CaseConverterView()) }
}

struct CaseConverterView: View {
    @State private var input = ""
    @State private var selected = 0

    private let modes = ["UPPER", "lower", "Title Case", "camelCase", "snake_case", "kebab-case"]

    private var result: String {
        guard !input.isEmpty else { return "" }
        switch selected {
        case 0: return input.uppercased()
        case 1: return input.lowercased()
        case 2: return input.capitalized
        case 3:
            let parts = input.split { !$0.isLetter && !$0.isNumber }
            guard let first = parts.first else { return "" }
            return first.lowercased() + parts.dropFirst().map { $0.capitalized }.joined()
        case 4:
            return input.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: "_")
        case 5:
            return input.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: "-")
        default: return input
        }
    }

    var body: some View {
        ToolLayout {
            SettingsGroup {
                InputField(placeholder: "Исходный текст", text: $input, isMultiline: true)
                SettingsDivider()
                Picker("Регистр", selection: $selected) {
                    ForEach(0..<modes.count, id: \.self) { i in Text(modes[i]).tag(i) }
                }
                .pickerStyle(.menu)
                .padding(Theme.rowInset)
            }
            ResultGroup(title: "Результат", value: result)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                IconAction(title: "Копировать результат", icon: "doc.on.doc") {
                    UIPasteboard.general.string = result
                    Haptic.success()
                }
            }
        }
    }
}
