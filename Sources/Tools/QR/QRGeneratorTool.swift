import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRGeneratorTool: Tool {
    let id = "qrgen"
    let name = "QR Generator"
    let icon = "qrcode"
    let category: ToolCategory = .qr
    let description = "Create QR codes"

    var content: AnyView { AnyView(QRGeneratorView()) }
}

struct QRGeneratorView: View {
    @State private var text = ""
    @State private var image: UIImage?

    var body: some View {
        ToolLayout(primaryTitle: "Создать QR-код", primaryAction: generate) {
            SettingsGroup {
                InputField(placeholder: "Текст или URL", text: $text, isMultiline: true)
                    .onChange(of: text) { _ in generate() }
            }
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(20)
                    .background(Theme.qrBackground, in: RoundedRectangle(cornerRadius: Theme.groupRadius))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("QR-код для введённого текста")
                    .contextMenu {
                        Button {
                            UIPasteboard.general.image = image
                            Haptic.success()
                        } label: { Label("Копировать изображение", systemImage: "doc.on.doc") }
                    }
            } else {
                EmptyStateView(title: "QR-код", message: "Введи текст или ссылку.")
            }
        }
    }

    private func generate() {
        guard !text.isEmpty else {
            image = nil
            return
        }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        if let output = filter.outputImage {
            let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            if let cg = context.createCGImage(scaled, from: scaled.extent) {
                image = UIImage(cgImage: cg)
                Haptic.success()
            }
        }
    }
}
