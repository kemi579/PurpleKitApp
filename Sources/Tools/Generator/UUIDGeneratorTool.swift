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
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Count: \(Int(count))")
                        .foregroundColor(Theme.textSecondary)
                    Slider(value: $count, in: 1...20, step: 1)
                        .tint(Theme.primaryLight)
                }

                PurpleButton(title: "Generate", icon: "arrow.clockwise") {
                    generate()
                }

                ForEach(uuids, id: \.self) { uuid in
                    ResultBox(title: "UUID", value: uuid) {
                        UIPasteboard.general.string = uuid
                        Haptic.success()
                    }
                }
            }
            .padding()
            .onAppear { generate() }
        }
    }

    private func generate() {
        uuids = (0..<Int(count)).map { _ in UUID().uuidString }
        Haptic.success()
    }
}
