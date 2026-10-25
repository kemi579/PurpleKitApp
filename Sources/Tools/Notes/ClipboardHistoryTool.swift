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
        ToolLayout {
            if items.isEmpty {
                EmptyStateView(title: "История пуста", message: "Здесь сохраняется текст буфера обмена, пока открыт этот экран.")
            } else {
                SettingsGroup {
                    ForEach(items) { item in
                        Button {
                            UIPasteboard.general.string = item.text
                            Haptic.success()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.text).font(.body).foregroundStyle(Theme.primaryText)
                                    .multilineTextAlignment(.leading)
                                Text(item.date, style: .relative).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(Theme.rowInset)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Копирует текст в буфер обмена")
                        .contextMenu {
                            Button(role: .destructive) {
                                items.removeAll { $0.id == item.id }
                                save()
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                        if item.id != items.last?.id { SettingsDivider() }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                IconAction(title: "Очистить историю", icon: "trash") {
                    items = []; save(); Haptic.light()
                }
            }
        }
        .onAppear { load(); startMonitoring() }
        .onDisappear { timer?.invalidate(); timer = nil }
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
