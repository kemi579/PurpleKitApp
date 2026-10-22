import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct HashTool: Tool {
    let id = "hash"
    let name = "Hash Calculator"
    let icon = "number.square"
    let category: ToolCategory = .hash
    let description = "MD5, SHA-1, SHA-256"

    var content: AnyView { AnyView(HashView()) }
}

struct HashView: View {
    @State private var input = ""
    @State private var md5 = ""
    @State private var sha1 = ""
    @State private var sha256 = ""
    @State private var showFilePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PurpleTextField(placeholder: "Text to hash…", text: $input, isMultiline: true)
                    .onChange(of: input) { _ in computeText() }

                PurpleButton(title: "Hash File", icon: "doc", style: .secondary) {
                    showFilePicker = true
                }

                ResultBox(title: "MD5", value: md5) {}
                ResultBox(title: "SHA-1", value: sha1) {}
                ResultBox(title: "SHA-256", value: sha256) {}

                PurpleButton(title: "Clear", icon: "trash", style: .secondary) {
                    input = ""; md5 = ""; sha1 = ""; sha256 = ""
                }
            }
            .padding()
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                hashFile(url)
            case .failure:
                Haptic.error()
            }
        }
    }

    private func computeText() {
        guard !input.isEmpty, let data = input.data(using: .utf8) else {
            md5 = ""; sha1 = ""; sha256 = ""
            return
        }
        md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hashFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            input = "[File: \(url.lastPathComponent)]"
            Haptic.success()
        } catch {
            Haptic.error()
        }
    }
}
