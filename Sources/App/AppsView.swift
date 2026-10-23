import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
    @State private var isEditing = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var busyID: String?
    @State private var path = NavigationPath()
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var menuTarget: LibraryIPA?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    searchBar
                    segmentControl
                    sectionHeader

                    if let statusMessage {
                        banner(statusMessage, color: Theme.success)
                    }
                    if let errorMessage {
                        banner(errorMessage, color: Theme.warning)
                    }
                    if !certs.isCertHealthy && certs.isLoggedIn {
                        banner(certs.certStatusText, color: Theme.warning)
                    } else if !certs.isLoggedIn {
                        banner("Войди в Apple ID (Настройки) и запроси сертификат.", color: Theme.warning)
                    }

                    contentList
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: LibraryIPA.self) { file in
                AppDetailView(
                    file: file,
                    isSigned: signedFiles.contains(where: { $0.id == file.id }),
                    busy: busyID == file.id,
                    onSign: { Task { await sign(file) } },
                    onSignAndInstall: { Task { await install(file) } },
                    onExport: { share(file) }
                )
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .confirmationDialog(menuTarget?.displayName ?? "", isPresented: Binding(
                get: { menuTarget != nil },
                set: { if !$0 { menuTarget = nil } }
            ), titleVisibility: .visible) {
                if let file = menuTarget {
                    Button("Sign & Install") { Task { await install(file) } }
                    Button("Знак") { Task { await sign(file) } }
                    Button("Экспорт") { share(file) }
                    Button("Получить информацию") { path.append(file) }
                    Button("Удалить", role: .destructive) { deleteOne(file) }
                    Button("Отмена", role: .cancel) {}
                }
            }
            .onAppear(perform: reload)
        }
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation { isEditing.toggle() }
            } label: {
                Text(isEditing ? "Готово" : "Править")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                isImporterPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .overlay(alignment: .bottom) {
            Text("Библиотека")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 44)
                .padding(.bottom, 4)
        }
        .padding(.bottom, 44)
    }

    private var searchBar: some View {
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.14)))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var segmentControl: some View {
        HStack(spacing: 0) {
            ForEach(LibrarySegment.allCases) { seg in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { segment = seg }
                } label: {
                    Text(seg.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(segment == seg ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if segment == seg {
                                Capsule().fill(Color(white: 0.28))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(white: 0.12)))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var sectionHeader: some View {
        HStack {
            Text(segment.rawValue)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Text("\(filteredList.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var contentList: some View {
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
                    Button {
                        if !isEditing { menuTarget = file }
                    } label: {
                        LibraryRow(file: file)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.black)
                    .listRowSeparatorTint(Color.white.opacity(0.08))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { deleteOne(file) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button { Task { await install(file) } } label: {
                            Label("Sign & Install", systemImage: "arrow.down.app.fill")
                        }
                        Button { Task { await sign(file) } } label: {
                            Label("Знак", systemImage: "signature")
                        }
                        Button { share(file) } label: {
                            Label("Экспорт", systemImage: "square.and.arrow.up")
                        }
                        Button { path.append(file) } label: {
                            Label("Получить информацию", systemImage: "info.circle")
                        }
                        Divider()
                        Button(role: .destructive) { deleteOne(file) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
    }

    private var filteredList: [LibraryIPA] {
        let base = segment == .downloaded ? importedFiles : signedFiles
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.displayName.lowercased().contains(q) ||
            ($0.bundleID?.lowercased().contains(q) ?? false)
        }
    }

    private func reload() {
        Task {
            importedFiles = LibraryIPALoader.load(in: "ImportedIPAs")
            signedFiles = LibraryIPALoader.load(in: "SignedIPAs")
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

    private func deleteOne(_ file: LibraryIPA) {
        try? FileManager.default.removeItem(at: file.url)
        reload()
    }

    private func share(_ file: LibraryIPA) {
        exportURL = file.url
        showShare = true
    }

    private func sign(_ file: LibraryIPA) async {
        busyID = file.id
        defer { busyID = nil }
        do {
            let signed = try await signer.sign(ipaURL: file.url)
            statusMessage = "Подписано: \(signed.lastPathComponent)"
            errorMessage = nil
            segment = .signed
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

enum LibraryIPALoader {
    static func load(in folder: String) -> [LibraryIPA] {
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
                    let meta = IPAMetadata.load(ipaURL: url)
                    return LibraryIPA(
                        url: url,
                        size: Int64(values?.fileSize ?? 0),
                        displayName: meta.displayName,
                        version: meta.version,
                        bundleID: meta.bundleID,
                        iconPath: meta.iconPath
                    )
                }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            return []
        }
    }
}

struct LibraryIPA: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let displayName: String
    let version: String?
    let bundleID: String?
    let iconPath: String?

    var id: String { url.path }

    var subtitle: String {
        let ver = version.map { "\($0) · " } ?? ""
        let bid = bundleID ?? url.lastPathComponent
        return "\(ver)\(bid)"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(url.path) }
    static func == (lhs: LibraryIPA, rhs: LibraryIPA) -> Bool { lhs.url.path == rhs.url.path }
}

struct LibraryRow: View {
    let file: LibraryIPA

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(path: file.iconPath)
                .frame(width: 54, height: 54)

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
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.vertical, 6)
    }
}

struct AppIconView: View {
    let path: String?

    var body: some View {
        Group {
            if let path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.primary, Theme.primaryLight], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "app.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AppDetailView: View {
    @EnvironmentObject var certs: CertificateStore
    let file: LibraryIPA
    let isSigned: Bool
    let busy: Bool
    let onSign: () -> Void
    let onSignAndInstall: () -> Void
    let onExport: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Настройка")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            AppIconView(path: file.iconPath)
                                .frame(width: 64, height: 64)
                            Spacer()
                        }
                        .padding(16)

                        divider
                        row("Имя", file.displayName)
                        divider
                        row("Идентификатор", file.bundleID ?? "—")
                        divider
                        row("Версия", file.version ?? "—")
                    }
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.12)))
                    .padding(.horizontal, 16)

                    Text("Подписание")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(certs.appleID.isEmpty ? "Нет Apple ID" : certs.appleID)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text(certs.certName.isEmpty ? "Нет сертификата" : certs.certName)
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)

                        HStack(spacing: 10) {
                            statusChip(
                                text: certs.isCertHealthy ? "Valid" : (certs.isLoggedIn ? "No cert" : "Sign in"),
                                color: certs.isCertHealthy ? Theme.success : Theme.warning,
                                icon: certs.isCertHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                            )
                            if let days = certs.daysLeft {
                                statusChip(
                                    text: "\(days) дней",
                                    color: days > 3 ? Theme.success : Theme.error,
                                    icon: "clock.fill"
                                )
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.12)))
                    .padding(.horizontal, 16)

                    Text("Передовой")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        navRow("Модифицировать")
                        divider
                        navRow("Характеристики")
                    }
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.12)))
                    .padding(.horizontal, 16)

                    VStack(spacing: 12) {
                        Button(action: onSign) {
                            Text(busy ? "Подписание…" : "Начните подписание")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Capsule().fill(Color.accentColor))
                        }
                        .disabled(busy)

                        Button(action: onSignAndInstall) {
                            Text(busy ? "Установка…" : "Sign & Install")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Theme.primary))
                        }
                        .disabled(busy)

                        Button(action: onExport) {
                            Text("Экспорт IPA")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(file.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сброс") {}
                    .foregroundColor(.white)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 16)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func navRow(_ title: String) -> some View {
        HStack {
            Text(title).foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func statusChip(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.85)))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

typealias AppsView = LibraryView
