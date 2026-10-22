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
        ScrollView {
            VStack(spacing: 20) {
                PurpleTextField(placeholder: "Text or URL…", text: $text, isMultiline: true)
                    .onChange(of: text) { _ in generate() }

                if let image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.surfaceElevated)
                        .frame(width: 220, height: 220)
                        .overlay(
                            Image(systemName: "qrcode")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.textSecondary)
                        )
                }

                PurpleButton(title: "Generate", icon: "qrcode") {
                    generate()
                }

                if image != nil {
                    PurpleButton(title: "Copy Image", icon: "doc.on.doc", style: .secondary) {
                        if let image {
                            UIPasteboard.general.image = image
                            Haptic.success()
                        }
                    }
                }
            }
            .padding()
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
