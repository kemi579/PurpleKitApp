import SwiftUI

struct URLEncodeTool: Tool {
    let id = "urlencode"
    let name = "URL Encode"
    let icon = "link"
    let category: ToolCategory = .text
    let description = "URL encode & decode"

    var content: AnyView { AnyView(URLEncodeView()) }
}

struct URLEncodeView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var mode = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    Text("Encode").tag(0)
                    Text("Decode").tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in process() }

                PurpleTextField(placeholder: "Input…", text: $input, isMultiline: true)
                    .onChange(of: input) { _ in process() }

                ResultBox(title: "Result", value: output) {}

                HStack(spacing: 12) {
                    PurpleButton(title: "Copy", icon: "doc.on.doc") {
                        UIPasteboard.general.string = output
                        Haptic.success()
                    }
                    PurpleButton(title: "Clear", icon: "trash", style: .secondary) {
                        input = ""; output = ""
                    }
                }
            }
            .padding()
        }
    }

    private func process() {
        guard !input.isEmpty else { output = ""; return }
        if mode == 0 {
            output = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        } else {
            output = input.removingPercentEncoding ?? input
        }
    }
}
