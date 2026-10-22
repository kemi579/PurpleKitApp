import SwiftUI

struct PasswordGeneratorTool: Tool {
    let id = "password"
    let name = "Password Generator"
    let icon = "key.fill"
    let category: ToolCategory = .generator
    let description = "Strong random passwords"

    var content: AnyView { AnyView(PasswordGeneratorView()) }
}

struct PasswordGeneratorView: View {
    @State private var length: Double = 16
    @State private var useUpper = true
    @State private var useLower = true
    @State private var useDigits = true
    @State private var useSymbols = true
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ResultBox(title: "Password", value: password) {}

                VStack(alignment: .leading, spacing: 8) {
                    Text("Length: \(Int(length))")
                        .foregroundColor(Theme.textSecondary)
                    Slider(value: $length, in: 8...64, step: 1)
                        .tint(Theme.primaryLight)
                }

                Toggle("Uppercase (A-Z)", isOn: $useUpper).tint(Theme.primary)
                Toggle("Lowercase (a-z)", isOn: $useLower).tint(Theme.primary)
                Toggle("Digits (0-9)", isOn: $useDigits).tint(Theme.primary)
                Toggle("Symbols (!@#…)", isOn: $useSymbols).tint(Theme.primary)

                PurpleButton(title: "Generate", icon: "arrow.clockwise") {
                    generate()
                }

                PurpleButton(title: "Copy", icon: "doc.on.doc", style: .secondary) {
                    UIPasteboard.general.string = password
                    Haptic.success()
                }
            }
            .padding()
            .onAppear { generate() }
        }
    }

    private func generate() {
        var charset = ""
        if useUpper { charset += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        if useLower { charset += "abcdefghijklmnopqrstuvwxyz" }
        if useDigits { charset += "0123456789" }
        if useSymbols { charset += "!@#$%^&*()-_=+[]{}|;:,.<>?" }
        guard !charset.isEmpty else {
            password = ""
            return
        }
        let chars = Array(charset)
        password = String((0..<Int(length)).map { _ in chars.randomElement()! })
        Haptic.success()
    }
}
