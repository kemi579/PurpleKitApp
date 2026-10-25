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
        ToolLayout(primaryTitle: "Сгенерировать", primaryAction: generate) {
            ResultGroup(title: "Пароль", value: password)
            SettingsGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Длина: \(Int(length))").font(.body)
                    Slider(value: $length, in: 8...64, step: 1)
                        .accessibilityLabel("Длина пароля")
                }
                .padding(Theme.rowInset)
                SettingsDivider()
                Toggle("Заглавные буквы (A–Z)", isOn: $useUpper).padding(Theme.rowInset)
                SettingsDivider()
                Toggle("Строчные буквы (a–z)", isOn: $useLower).padding(Theme.rowInset)
                SettingsDivider()
                Toggle("Цифры (0–9)", isOn: $useDigits).padding(Theme.rowInset)
                SettingsDivider()
                Toggle("Символы", isOn: $useSymbols).padding(Theme.rowInset)
            }
        }
        .onAppear { generate() }
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
