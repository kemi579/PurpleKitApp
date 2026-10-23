import SwiftUI

@MainActor
struct ClipboardHistoryTool: Tool {
    let id = "clipboard"
    let name = "Clipboard History"
    let icon = "doc.on.clipboard"
    let category: ToolCategory = .notes
    let description = "Local clipboard history"

    var content: AnyView { AnyView(ClipboardHistoryView()) }
}

@MainActor
struct ClipboardHistoryView: View {
    @State private var items: [ClipItem] = []
    @State private var timer: Timer?

    private let key = "PurpleKit.clipboard"
    private let maxItems = 50

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History (local only)")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button("Clear All") {
                    items = []
                    save()
                    Haptic.light()
                }
                .font(.caption)
                .foregroundColor(Theme.error)
            }
            .padding()

            if items.isEmpty {
                EmptyStateView(icon: "doc.on.clipboard", title: "Empty", message: "Copy something to start history.")
            } else {
                List {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(3)
                            Text(item.date, style: .relative)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.surfaceElevated)
                        .onTapGesture {
                            UIPasteboard.general.string = item.text
                            Haptic.success()
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                items.removeAll { $0.id == item.id }
                                save()
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
        .onAppear {
            load()
            startMonitoring()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                checkClipboard()
            }
        }
    }

    @MainActor
    private func checkClipboard() {
        guard let str = UIPasteboard.general.string, !str.isEmpty else { return }
        if items.first?.text == str { return }
        items.insert(ClipItem(text: str), at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct ClipItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
    }
}
