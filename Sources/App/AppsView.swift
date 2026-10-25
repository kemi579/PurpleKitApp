import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum LibrarySegment: String, CaseIterable, Identifiable {
    case downloaded = "Импортированные"
    case signed = "Подписанные"
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var certs: CertificateStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var installer = DeviceInstaller.shared
    @ObservedObject private var signer = IPASigningService.shared
    @AppStorage("PurpleKit.library.sortBySize") private var sortBySize = false

    var onOpenSettings: () -> Void = {}

    @State private var segment: LibrarySegment = .downloaded
    @State private var search = ""
    @State private var importedFiles: [LibraryIPA] = []
    @State private var signedFiles: [LibraryIPA] = []
    @State private var isImporterPresented = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var busyID: String?
    @State private var path = NavigationPath()
    @State private var exportFile: LibraryIPA?
    @State private var pendingDeletion: LibraryIPA?
    @State private var isLoading = false

    private var isBusy: Bool {
        isLoading || busyID != nil || signer.isWorking || installer.isWorking
    }

    private var filteredList: [LibraryIPA] {
        let base = segment == .downloaded ? importedFiles : signedFiles
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = base.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || ($0.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
        return matches.sorted {
            if sortBySize && $0.size != $1.size { return $0.size > $1.size }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ToolLayout(primaryTitle: "Импортировать IPA", isBusy: isBusy,
                       primaryAction: { isImporterPresented = true }) {
                Picker("Тип IPA", selection: $segment) {
                    ForEach(LibrarySegment.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)

                SectionHeading(title: "\(segment.rawValue) · \(filteredList.count)")
                if isLoading {
                    ProgressView("Чтение библиотеки…")
                } else if isBusy {
                    LibraryNotice(title: "Выполняется операция",
                                  message: signer.progressText.isEmpty ? installer.status : signer.progressText,
                                  color: Theme.secondaryText, isProgress: true)
                }
                if let errorMessage {
                    LibraryNotice(title: "Не получилось", message: errorMessage, color: Theme.error)
                } else if let statusMessage {
                    LibraryNotice(title: "Готово", message: statusMessage, color: Theme.success)
                }

                if !filteredList.isEmpty {
                    SettingsGroup {
                        ForEach(filteredList) { file in
                            NavigationLink(value: file) {
                                LibraryRow(file: file, isSigned: segment == .signed)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { path.append(file) } label: {
                                    Label("Сведения", systemImage: "info.circle")
                                }
                                Button { Task { await sign(file) } } label: {
                                    Label("Подписать", systemImage: "signature")
                                }
                                .disabled(isBusy)
                                Button { Task { await install(file) } } label: {
                                    Label(segment == .signed ? "Установить IPA" : "Подписать и установить",
                                          systemImage: "arrow.down.app")
                                }
                                .disabled(isBusy)
                                Button { exportFile = file } label: {
                                    Label("Экспортировать", systemImage: "square.and.arrow.up")
                                }
                                Button(role: .destructive) { pendingDeletion = file } label: {
                                    Label("Удалить IPA", systemImage: "trash")
                                }
                                .disabled(isBusy)
                            }
                            if file.id != filteredList.last?.id { SettingsDivider(leading: 72) }
                        }
                    }
                } else if !isLoading {
                    EmptyStateView(title: search.isEmpty ? "Библиотека пуста" : "Ничего не найдено",
                                   message: search.isEmpty ? "Импортируй IPA из приложения «Файлы»." : "Попробуй другое название или Bundle ID.")
                }
                Button(action: onOpenSettings) {
                    SettingsRow(title: "Настройки подключения", value: certs.certStatusText)
                }
                .buttonStyle(.plain)
                Text("Подписанный IPA ещё не означает установленное приложение.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .navigationTitle("Библиотека")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "Поиск IPA")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }.frame(minHeight: 44)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    IconAction(title: "Обновить библиотеку", icon: "arrow.clockwise", action: reload).disabled(isBusy)
                    Menu {
                        Picker("Сортировка", selection: $sortBySize) {
                            Text("По названию").tag(false)
                            Text("Сначала большие").tag(true)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Сортировка IPA")
                }
            }
            .navigationDestination(for: LibraryIPA.self) { file in
                AppDetailView(file: file,
                              isSigned: signedFiles.contains { $0.id == file.id },
                              busy: isBusy,
                              onSign: { Task { await sign(file) } },
                              onSignAndInstall: { Task { await install(file) } },
                              onExport: { exportFile = file },
                              statusMessage: statusMessage, errorMessage: errorMessage)
            }
            .fileImporter(isPresented: $isImporterPresented,
                          allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                          allowsMultipleSelection: true, onCompletion: handleImport)
            .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]) }
            .alert("Удалить IPA?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )) {
                Button("Удалить", role: .destructive) {
                    if let file = pendingDeletion { deleteOne(file) }
                    pendingDeletion = nil
                }
                Button("Отмена", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Файл «\(pendingDeletion?.displayName ?? "")» будет удалён из библиотеки. Установленное приложение останется на устройстве.")
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                (LibraryIPALoader.load(in: "ImportedIPAs"), LibraryIPALoader.load(in: "SignedIPAs"))
            }.value
            importedFiles = snapshot.0
            signedFiles = snapshot.1
            isLoading = false
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        statusMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            do {
                let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let directory = docs.appendingPathComponent("ImportedIPAs", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var imported = 0
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard url.pathExtension.lowercased() == "ipa" else { continue }
                    var destination = directory.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        destination = directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).ipa")
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    imported += 1
                }
                segment = .downloaded
                search = ""
                statusMessage = imported > 0 ? "Добавлено файлов: \(imported)" : nil
            } catch {
                errorMessage = error.localizedDescription
            }
            reload()
        }
    }

    private func deleteOne(_ file: LibraryIPA) {
        guard !isBusy else { return }
        do {
            try FileManager.default.removeItem(at: file.url)
            statusMessage = "«\(file.displayName)» удалён из библиотеки."
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sign(_ file: LibraryIPA) async {
        guard !isBusy else { return }
        busyID = file.id
        errorMessage = nil
        statusMessage = nil
        defer { busyID = nil }
        do {
            let signed = try await signer.sign(ipaURL: file.url)
            statusMessage = "Подписано: \(signed.lastPathComponent)"
            segment = .signed
            reload()
            Haptic.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptic.error()
        }
    }

    private func install(_ file: LibraryIPA) async {
        guard !isBusy else { return }
        busyID = file.id
        errorMessage = nil
        statusMessage = nil
        defer { busyID = nil }
        do {
            if signedFiles.contains(where: { $0.id == file.id }) {
                guard let bundleID = file.bundleID else { throw DeviceInstaller.InstallError.missingBundleID }
                try await installer.installSigned(ipaURL: file.url, bundleID: bundleID)
            } else {
                try await installer.signAndInstall(ipaURL: file.url)
            }
            statusMessage = installer.status
            reload()
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

struct LibraryIPA: Identifiable, Hashable, Sendable {
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
    var isSigned = false

    var body: some View {
        HStack(spacing: 16) {
            AppIconView(path: file.iconPath)
            VStack(alignment: .leading, spacing: 8) {
                Text(file.displayName).font(.body).foregroundStyle(Theme.primaryText)
                Text(file.subtitle).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if isSigned { PillBadge(text: "Подписан", color: Theme.success) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
        }
        .padding(Theme.rowInset)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AppIconView: View {
    let path: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let path, let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface)
                    .overlay {
                        Image(systemName: "app").font(.title2).foregroundStyle(Theme.secondaryText)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

private struct LibraryNotice: View {
    let title: String
    let message: String
    let color: Color
    var isProgress = false

    var body: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 8) {
                if isProgress { ProgressView(title) }
                else { Text(title).font(.headline).foregroundStyle(color) }
                Text(message).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.rowInset)
            .accessibilityElement(children: .combine)
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var certs: CertificateStore
    @ObservedObject private var installer = DeviceInstaller.shared
    @ObservedObject private var signer = IPASigningService.shared
    let file: LibraryIPA
    let isSigned: Bool
    let busy: Bool
    let onSign: () -> Void
    let onSignAndInstall: () -> Void
    let onExport: () -> Void
    var statusMessage: String? = nil
    var errorMessage: String? = nil

    var body: some View {
        ToolLayout(primaryTitle: busy ? "Выполняется операция…" : (isSigned ? "Установить IPA" : "Подписать и установить"),
                   isBusy: busy, primaryAction: onSignAndInstall) {
            SectionHeading(title: "Приложение")
            SettingsGroup {
                HStack {
                    AppIconView(path: file.iconPath, size: 64)
                    Spacer()
                }
                .padding(Theme.rowInset)
                SettingsDivider()
                SettingsRow(title: "Имя", value: file.displayName, showsChevron: false)
                SettingsDivider()
                SettingsRow(title: "Идентификатор", value: file.bundleID ?? "—", showsChevron: false)
                SettingsDivider()
                SettingsRow(title: "Версия", value: file.version ?? "—", showsChevron: false)
                SettingsDivider()
                SettingsRow(title: "Размер", value: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file),
                            showsChevron: false)
            }
            SectionHeading(title: "Подписание")
            SettingsGroup {
                SettingsRow(title: "Apple ID", value: certs.appleID.isEmpty ? "Не подключён" : certs.appleID,
                            showsChevron: false)
                SettingsDivider()
                SettingsRow(title: "Сертификат", value: certs.certName.isEmpty ? "Не выдан" : certs.certName,
                            showsChevron: false)
                StatusBadges {
                    PillBadge(text: certs.isCertHealthy ? "Valid" : certs.certStatusText,
                              color: certs.isCertHealthy ? Theme.success : Theme.error)
                    if let days = certs.daysLeft {
                        PillBadge(text: "\(days) дней", color: days <= 2 ? Theme.error : Theme.secondaryText)
                    }
                }
            }
            if busy {
                LibraryNotice(title: "Выполняется операция",
                              message: signer.progressText.isEmpty ? installer.status : signer.progressText,
                              color: Theme.secondaryText, isProgress: true)
            } else if let errorMessage {
                LibraryNotice(title: "Не получилось", message: errorMessage, color: Theme.error)
            } else if let statusMessage {
                LibraryNotice(title: "Готово", message: statusMessage, color: Theme.success)
            }
        }
        .navigationTitle(file.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: onSign) { Label("Только подписать", systemImage: "signature") }.disabled(busy)
                    Button(action: onExport) { Label("Экспортировать IPA", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Действия с IPA")
            }
        }
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
