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
        ScrollView {
            VStack(spacing: 16) {
                PurpleTextField(placeholder: "Type or paste text…", text: $text, isMultiline: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard("Characters", "\(chars)")
                    statCard("No spaces", "\(charsNoSpaces)")
                    statCard("Words", "\(words)")
                    statCard("Lines", "\(lines)")
                }

                PurpleButton(title: "Clear", icon: "trash", style: .secondary) {
                    text = ""
                }
            }
            .padding()
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryGradient)
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
