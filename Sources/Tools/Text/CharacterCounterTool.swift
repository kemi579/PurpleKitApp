import SwiftUI

struct CharacterCounterTool: Tool {
    let id = "charcount"
    let name = "Character Counter"
    let icon = "textformat.123"
    let category: ToolCategory = .text
    let description = "Count chars, words, lines"

    var content: AnyView { AnyView(CharacterCounterView()) }
}

struct CharacterCounterView: View {
    @State private var text = ""

    private var chars: Int { text.count }
    private var charsNoSpaces: Int { text.replacingOccurrences(of: " ", with: "").count }
    private var words: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
    private var lines: Int {
        text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
    }

    var body: some View {
        ToolLayout {
            SettingsGroup {
                InputField(placeholder: "Текст", text: $text, isMultiline: true)
            }
            SettingsGroup {
                SettingsRow(title: "Символы", value: "\(chars)", showsChevron: false)
                SettingsDivider()
                SettingsRow(title: "Без пробелов", value: "\(charsNoSpaces)", showsChevron: false)
                SettingsDivider()
                SettingsRow(title: "Слова", value: "\(words)", showsChevron: false)
                SettingsDivider()
                SettingsRow(title: "Строки", value: "\(lines)", showsChevron: false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                IconAction(title: "Очистить", icon: "trash") { text = "" }
            }
        }
    }

}
