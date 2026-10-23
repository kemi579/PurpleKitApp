import SwiftUI
import UniformTypeIdentifiers

struct IPAImportView: View {
    @State private var isImporterPresented = false
    @State private var importedFiles: [ImportedIPA] = []
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var fileToDelete: ImportedIPA?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Soft ambient orbs for nested screens
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
                        Text("Import and keep IPA packages inside PurpleKit.")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }

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

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .glassCard(cornerRadius: 14, intensity: 0.8)
                    }

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
                                .background {
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                }
                        }

                        if importedFiles.isEmpty {
                            EmptyStateView(
                                icon: "shippingbox",
                                title: "Your library is empty",
                                message: "Imported IPA files will be listed here."
                            )
                            .padding(.vertical, 4)
                        } else {
                            ForEach(importedFiles) { file in
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

                                    Button(role: .destructive) {
                                        fileToDelete = file
                                        showDeleteConfirmation = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(Theme.textSecondary)
                                            .padding(8)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete \(file.name)")
                                }
                                .padding(.vertical, 4)

                                if file.id != importedFiles.last?.id {
                                    Divider().overlay(Color.white.opacity(0.08))
                                }
                            }
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 18)

                    Label(
                        "Current scope: this screen copies and stores IPA files only. It does not extract app metadata, verify signatures, sign apps, pair a device, or install packages.",
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
        .onAppear(perform: reloadFiles)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = "Could not import file: \(error.localizedDescription)"
        case .success(let urls):
            do {
                for url in urls {
                    try importFile(from: url)
                }
                reloadFiles()
            } catch {
                errorMessage = error.localizedDescription
                reloadFiles()
            }
        }
    }

    private func importFile(from sourceURL: URL) throws {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

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
        case notIPA
        case invalidArchive
        var errorDescription: String? {
            switch self {
            case .notIPA:
                return "Only files with the .ipa extension can be imported."
            case .invalidArchive:
                return "This file does not have a valid ZIP/IPA signature. It was not imported."
            }
        }
    }
}
