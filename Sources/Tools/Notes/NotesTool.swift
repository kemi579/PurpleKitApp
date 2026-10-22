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
        VStack(spacing: 0) {
            HStack {
                PurpleTextField(placeholder: "New note…", text: $newText)
                Button {
                    add()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.primaryGradient)
                }
            }
            .padding()

            if notes.isEmpty {
                EmptyStateView(icon: "note.text", title: "No notes", message: "Add your first quick note.")
            } else {
                List {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.text)
                                .foregroundColor(Theme.textPrimary)
                            Text(note.date, style: .relative)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.surfaceElevated)
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
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
