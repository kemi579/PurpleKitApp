import SwiftUI

struct UUIDGeneratorTool: Tool {
    let id = "uuid"
    let name = "UUID Generator"
    let icon = "barcode"
    let category: ToolCategory = .generator
    let description = "Generate UUIDs"

    var content: AnyView { AnyView(UUIDGeneratorView()) }
}

struct UUIDGeneratorView: View {
    @State private var uuids: [String] = []
    @State private var count: Double = 1

    var body: some View {
        ToolLayout(primaryTitle: "Сгенерировать", primaryAction: generate) {
            SettingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Количество: \(Int(count))").font(.body)
                    Slider(value: $count, in: 1...20, step: 1).accessibilityLabel("Количество UUID")
                }
                .padding(Theme.rowInset)
            }
            ForEach(uuids, id: \.self) { uuid in
                ResultGroup(title: "UUID", value: uuid) {
                    UIPasteboard.general.string = uuid
                    Haptic.success()
                }
            }
        }
        .onAppear { generate() }
    }

    private func generate() {
        uuids = (0..<Int(count)).map { _ in UUID().uuidString }
        Haptic.success()
    }
}
