import SwiftUI

struct NotesTool: Tool {
    let id = "notes"
    let name = "Quick Notes"
    let icon = "note.text"
    let category: ToolCategory = .notes
    let description = "Local notes storage"

    var content: AnyView { AnyView(NotesView()) }
}

struct NotesView: View {
    @State private var notes: [Note] = []
    @State private var newText = ""

    private let key = "PurpleKit.notes"

    var body: some View {
        ToolLayout(primaryTitle: "Добавить заметку", primaryAction: add) {
            SettingsGroup { InputField(placeholder: "Новая заметка", text: $newText, isMultiline: true) }
            if notes.isEmpty {
                EmptyStateView(title: "Нет заметок", message: "Добавь первую заметку.")
            } else {
                SettingsGroup {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.text).font(.body).foregroundStyle(Theme.primaryText)
                                .textSelection(.enabled)
                            Text(note.date, style: .relative).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.rowInset)
                        .accessibilityElement(children: .combine)
                        .contextMenu {
                            Button { UIPasteboard.general.string = note.text } label: {
                                Label("Копировать", systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) { delete(note) } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        if note.id != notes.last?.id { SettingsDivider() }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    ClipboardHistoryView().navigationTitle("Буфер обмена")
                } label: {
                    Image(systemName: "doc.on.clipboard").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("История буфера обмена")
            }
        }
        .onAppear { load() }
    }

    private func add() {
        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        notes.insert(Note(text: t), at: 0)
        newText = ""
        save()
        Haptic.success()
    }

    private func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        save()
        Haptic.light()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct Note: Identifiable, Codable {
    let id: UUID
    var text: String
    let date: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
    }
}
