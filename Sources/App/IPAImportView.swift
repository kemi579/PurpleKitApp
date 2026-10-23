import SwiftUI
import UniformTypeIdentifiers
import SideSign

struct IPAImportView: View {
    @StateObject private var signer = IPASigningService.shared
    @EnvironmentObject private var certs: CertificateStore

    @State private var isImporterPresented = false
    @State private var importedFiles: [ImportedIPA] = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var fileToDelete: ImportedIPA?
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var busyID: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Circle()
                .fill(Theme.primary.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: -80, y: -120)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("IPA Library")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.primaryGradient)
                        Text("Import → Sign with your cert → Install")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }

                    // Status strip
                    HStack(spacing: 10) {
                        statusDot(certs.isLoggedIn && !certs.certName.isEmpty)
                        Text(certs.isLoggedIn
                              ? (certs.certName.isEmpty ? "Signed in · need certificate" : "Ready to sign")
                              : "Sign in required")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        if signer.deviceUDID.isEmpty {
                            Text("UDID missing")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(Theme.warning)
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 14, intensity: 0.8)

                    Button {
                        isImporterPresented = true
                    } label: {
                        GlassLinkCard(
                            icon: "square.and.arrow.down.fill",
                            title: "Import IPA",
                            subtitle: "Choose an .ipa file from Files",
                            iconColor: Theme.primaryLight
                        )
                    }
                    .buttonStyle(.plain)

                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.success)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .glassCard(cornerRadius: 14, intensity: 0.8)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .glassCard(cornerRadius: 14, intensity: 0.8)
                    }

                    if signer.isWorking {
                        HStack(spacing: 12) {
                            ProgressView().tint(Theme.primaryLight)
                            Text(signer.progressText.isEmpty ? "Working…" : signer.progressText)
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 16)
                    }

                    libraryCard

                    Label(
                        "Sign uses SideSign + your development certificate. Install opens TrollStore if present, otherwise Share the signed IPA to SideStore/AltStore.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .glassCard(cornerRadius: 14, intensity: 0.7)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("IPA Library")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .confirmationDialog(
            "Delete imported IPA?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let fileToDelete { delete(fileToDelete) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(fileToDelete?.name ?? "")
        }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .onAppear(perform: reloadFiles)
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Imported packages")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(importedFiles.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(Color.white.opacity(0.08)) }
            }

            if importedFiles.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "Your library is empty",
                    message: "Import an IPA, then Sign & Install."
                )
                .padding(.vertical, 4)
            } else {
                ForEach(importedFiles) { file in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.zipper")
                                .font(.title3)
                                .foregroundColor(Theme.neon)
                                .frame(width: 40, height: 40)
                                .background {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Theme.neon.opacity(0.12))
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(2)
                                Text(file.sizeDescription)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(Theme.textSecondary)
                            }

                            Spacer(minLength: 4)

                            Button {
                                fileToDelete = file
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 10) {
                            actionButton(
                                title: busyID == file.id + "-sign" ? "Signing…" : "Sign",
                                icon: "signature",
                                disabled: signer.isWorking
                            ) {
                                Task { await sign(file) }
                            }

                            actionButton(
                                title: busyID == file.id + "-install" ? "…" : "Sign & Install",
                                icon: "arrow.down.app.fill",
                                disabled: signer.isWorking
                            ) {
                                Task { await signAndInstall(file) }
                            }
                        }
                    }
                    .padding(.vertical, 6)

                    if file.id != importedFiles.last?.id {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
    }

    private func actionButton(title: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(.white)
            .background(Theme.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func statusDot(_ ok: Bool) -> some View {
        Circle()
            .fill(ok ? Theme.success : Theme.warning)
            .frame(width: 8, height: 8)
            .shadow(color: (ok ? Theme.success : Theme.warning).opacity(0.5), radius: 4)
    }

    // MARK: - Actions

    private func sign(_ file: ImportedIPA) async {
        errorMessage = nil
        statusMessage = nil
        busyID = file.id + "-sign"
        defer { busyID = nil }
        do {
            let signed = try await signer.sign(ipaURL: file.url)
            statusMessage = "Signed: \(signed.lastPathComponent)"
            shareURL = signed
            Haptic.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptic.error()
        }
    }

    private func signAndInstall(_ file: ImportedIPA) async {
        errorMessage = nil
        statusMessage = nil
        busyID = file.id + "-install"
        defer { busyID = nil }
        do {
            let signed = try await signer.sign(ipaURL: file.url)
            statusMessage = "Signed. Opening installer…"
            shareURL = signed

            // Try TrollStore first
            var opened = false
            for scheme in signer.installURLSchemes(for: signed) {
                if await UIApplication.shared.open(scheme) {
                    opened = true
                    statusMessage = "Opened TrollStore install."
                    break
                }
            }
            if !opened {
                // Share sheet → SideStore / Files / AltStore
                showShare = true
                statusMessage = "Share the signed IPA to SideStore or AltStore to install."
            }
            Haptic.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptic.error()
        }
    }

    // MARK: - Import / delete

    private func handleImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = "Could not import file: \(error.localizedDescription)"
        case .success(let urls):
            do {
                for url in urls { try importFile(from: url) }
                reloadFiles()
            } catch {
                errorMessage = error.localizedDescription
                reloadFiles()
            }
        }
    }

    private func importFile(from sourceURL: URL) throws {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        guard sourceURL.pathExtension.lowercased() == "ipa" else {
            throw ImportError.notIPA
        }

        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let signature = try handle.read(upToCount: 4) ?? Data()
        guard signature.count == 4,
              signature[signature.startIndex] == 0x50,
              signature[signature.startIndex + 1] == 0x4B,
              [0x03, 0x05, 0x07].contains(signature[signature.startIndex + 2]),
              [0x04, 0x06, 0x08].contains(signature[signature.startIndex + 3]) else {
            throw ImportError.invalidArchive
        }

        let destinationDirectory = try Self.importDirectory()
        var destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let suffix = String(UUID().uuidString.prefix(8))
            destinationURL = destinationDirectory.appendingPathComponent("\(stem)-\(suffix).ipa")
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func reloadFiles() {
        do {
            let directory = try Self.importDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            importedFiles = urls
                .filter { $0.pathExtension.lowercased() == "ipa" }
                .compactMap { url in
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values?.isRegularFile == true else { return nil }
                    return ImportedIPA(url: url, size: Int64(values?.fileSize ?? 0))
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = "Could not load the IPA library: \(error.localizedDescription)"
        }
    }

    private func delete(_ file: ImportedIPA) {
        do {
            try FileManager.default.removeItem(at: file.url)
            importedFiles.removeAll { $0.id == file.id }
            errorMessage = nil
        } catch {
            errorMessage = "Could not delete \(file.name): \(error.localizedDescription)"
        }
    }

    private static func importDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent("ImportedIPAs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private struct ImportedIPA: Identifiable {
        let url: URL
        let size: Int64
        var id: String { url.lastPathComponent }
        var name: String { url.lastPathComponent }
        var sizeDescription: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    private enum ImportError: LocalizedError {
        case notIPA, invalidArchive
        var errorDescription: String? {
            switch self {
            case .notIPA: return "Only .ipa files can be imported."
            case .invalidArchive: return "Invalid IPA/ZIP signature."
            }
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
