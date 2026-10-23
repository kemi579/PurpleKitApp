import SwiftUI
import UniformTypeIdentifiers

/// Library tab — matches screenshot: title, search, Downloaded / Signed segments, app rows.
enum LibrarySegment: String, CaseIterable, Identifiable {
    case downloaded = "Downloaded Apps"
    case signed = "Signed Apps"
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject var certs: CertificateStore
    @StateObject private var installer = DeviceInstaller.shared
    @StateObject private var signer = IPASigningService.shared

    @State private var segment: LibrarySegment = .downloaded
    @State private var search = ""
    @State private var importedFiles: [LibraryIPA] = []
    @State private var signedFiles: [LibraryIPA] = []
    @State private var isImporterPresented = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var busyID: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Large title row + add
                    HStack(alignment: .center) {
                        Text("Библиотека")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            isImporterPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.textTertiary)
                        TextField("Поиск", text: $search)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.15))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Segment control
                    HStack(spacing: 0) {
                        ForEach(LibrarySegment.allCases) { seg in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { segment = seg }
                            } label: {
                                Text(seg.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(segment == seg ? .white : Theme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background {
                                        if segment == seg {
                                            Capsule().fill(Color(white: 0.22))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Capsule().fill(Color(white: 0.12)))
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    // Section header
                    HStack {
                        Text(segment.rawValue)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(filteredList.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(Theme.success)
                            .padding(.horizontal, 20)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(Theme.warning)
                            .padding(.horizontal, 20)
                    }

                    if filteredList.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 36))
                                .foregroundColor(Theme.textTertiary)
                            Text(segment == .downloaded ? "Нет загруженных IPA" : "Нет подписанных IPA")
                                .foregroundColor(Theme.textSecondary)
                            Button("Импорт IPA") { isImporterPresented = true }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.primaryLight)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredList) { file in
                                NavigationLink {
                                    LibraryDetailView(
                                        file: file,
                                        isSigned: segment == .signed,
                                        onSign: { Task { await sign(file) } },
                                        onInstall: { Task { await install(file) } },
                                        busy: busyID == file.id
                                    )
                                } label: {
                                    LibraryRow(file: file)
                                }
                                .listRowBackground(Color.black)
                                .listRowSeparatorTint(Color.white.opacity(0.08))
                            }
                            .onDelete(perform: delete)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationBarHidden(true)
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
            .onAppear(perform: reload)
        }
    }

    private var filteredList: [LibraryIPA] {
        let base = segment == .downloaded ? importedFiles : signedFiles
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.lowercased().contains(q) ||
            ($0.bundleID?.lowercased().contains(q) ?? false)
        }
    }

    private func reload() {
        importedFiles = loadIPAs(in: "ImportedIPAs")
        signedFiles = loadIPAs(in: "SignedIPAs")
    }

    private func loadIPAs(in folder: String) -> [LibraryIPA] {
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            return urls
                .filter { $0.pathExtension.lowercased() == "ipa" }
                .compactMap { url -> LibraryIPA? in
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values?.isRegularFile == true else { return nil }
                    return LibraryIPA(
                        url: url,
                        size: Int64(values?.fileSize ?? 0),
                        displayName: url.deletingPathExtension().lastPathComponent,
                        version: nil,
                        bundleID: nil
                    )
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            return []
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .failure(let e):
            errorMessage = e.localizedDescription
        case .success(let urls):
            do {
                let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let dir = docs.appendingPathComponent("ImportedIPAs", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard url.pathExtension.lowercased() == "ipa" else { continue }
                    var dest = dir.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        let stem = url.deletingPathExtension().lastPathComponent
                        dest = dir.appendingPathComponent("\(stem)-\(String(UUID().uuidString.prefix(6))).ipa")
                    }
                    try FileManager.default.copyItem(at: url, to: dest)
                }
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let list = filteredList
        for i in offsets {
            let file = list[i]
            try? FileManager.default.removeItem(at: file.url)
        }
        reload()
    }

    private func sign(_ file: LibraryIPA) async {
        busyID = file.id
        defer { busyID = nil }
        do {
            let signed = try await signer.sign(ipaURL: file.url)
            // Keep a copy under SignedIPAs
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("SignedIPAs", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(signed.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: signed, to: dest)
            statusMessage = "Signed: \(signed.lastPathComponent)"
            errorMessage = nil
            reload()
            Haptic.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptic.error()
        }
    }

    private func install(_ file: LibraryIPA) async {
        busyID = file.id
        defer { busyID = nil }
        do {
            try await installer.signAndInstall(ipaURL: file.url)
            statusMessage = installer.status
            errorMessage = nil
            Haptic.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptic.error()
        }
    }
}

struct LibraryIPA: Identifiable {
    let url: URL
    let size: Int64
    let displayName: String
    let version: String?
    let bundleID: String?
    var id: String { url.path }
    var name: String { displayName }
    var subtitle: String {
        let ver = version.map { "\($0) · " } ?? ""
        let bid = bundleID ?? url.lastPathComponent
        return "\(ver)\(bid)"
    }
}

struct LibraryRow: View {
    let file: LibraryIPA

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.primary, Theme.primaryLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "app.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(file.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct LibraryDetailView: View {
    let file: LibraryIPA
    let isSigned: Bool
    let onSign: () -> Void
    let onInstall: () -> Void
    let busy: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                LibraryRow(file: file)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 20)

                if !isSigned {
                    Button(action: onSign) {
                        labelButton(busy ? "Signing…" : "Sign")
                    }
                    .disabled(busy)
                    .padding(.horizontal, 20)
                }

                Button(action: onInstall) {
                    labelButton(busy ? "Installing…" : "Install")
                }
                .disabled(busy)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle(file.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labelButton(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Kept so older references compile.
typealias AppsView = LibraryView
