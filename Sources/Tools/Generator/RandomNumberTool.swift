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
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    PurpleTextField(placeholder: "Min", text: $minVal)
                    PurpleTextField(placeholder: "Max", text: $maxVal)
                }

                VStack(alignment: .leading) {
                    Text("Count: \(Int(count))")
                        .foregroundColor(Theme.textSecondary)
                    Slider(value: $count, in: 1...50, step: 1)
                        .tint(Theme.primaryLight)
                }

                PurpleButton(title: "Generate", icon: "dice") {
                    generate()
                }

                ForEach(results, id: \.self) { r in
                    ResultBox(title: "Result", value: r) {}
                }
            }
            .padding()
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
