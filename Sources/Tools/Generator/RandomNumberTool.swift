import SwiftUI

struct RandomNumberTool: Tool {
    let id = "random"
    let name = "Random Number"
    let icon = "dice.fill"
    let category: ToolCategory = .generator
    let description = "Random integers in range"

    var content: AnyView { AnyView(RandomNumberView()) }
}

struct RandomNumberView: View {
    @State private var minVal = "1"
    @State private var maxVal = "100"
    @State private var result = ""
    @State private var count: Double = 1
    @State private var results: [String] = []

    var body: some View {
        ToolLayout(primaryTitle: "Сгенерировать", primaryAction: generate) {
            SettingsGroup {
                InputField(placeholder: "Минимум", text: $minVal)
                SettingsDivider()
                InputField(placeholder: "Максимум", text: $maxVal)
                SettingsDivider()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Количество: \(Int(count))").font(.body)
                    Slider(value: $count, in: 1...50, step: 1).accessibilityLabel("Количество чисел")
                }
                .padding(Theme.rowInset)
            }
            if !results.isEmpty {
                ResultGroup(title: "Результаты", value: results.joined(separator: "\n"))
            }
        }
    }

    private func generate() {
        guard let min = Int(minVal), let max = Int(maxVal), min <= max else {
            results = ["Invalid range"]
            Haptic.error()
            return
        }
        results = (0..<Int(count)).map { _ in String(Int.random(in: min...max)) }
        Haptic.success()
    }
}
