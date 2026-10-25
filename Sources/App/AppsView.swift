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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var isBusy: Bool {
        busyID != nil || signer.isWorking || installer.isWorking
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    overview
                    searchBar
                    librarySection
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(LibraryBackground())
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryIPA.self) { file in
                AppDetailView(
                    file: file,
                    isSigned: signedFiles.contains { $0.id == file.id },
                    busy: isBusy,
                    onSign: { Task { await sign(file) } },
                    onSignAndInstall: { Task { await install(file) } },
                    onExport: { exportFile = file }
                )
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("PURPLEKIT", systemImage: "square.stack.3d.up.fill")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Theme.primaryLight)
                Spacer()
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceElevated, in: Circle())
                }
                .accessibilityLabel("Обновить библиотеку")
                .disabled(isBusy)
            }
            Text("Мои приложения")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("Твои IPA. Всё под рукой.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ТВОЯ БИБЛИОТЕКА")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.primaryLight)
                    Text("\(importedFiles.count + signedFiles.count) IPA")
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "square.stack.3d.up")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.primaryLight)
                    .padding(12)
                    .background(Theme.primary.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                Label("\(signedFiles.count) подписано", systemImage: "signature")
                Spacer(minLength: 8)
                Text(ByteCountFormatter.string(
                    fromByteCount: (importedFiles + signedFiles).reduce(Int64(0)) { $0 + $1.size },
                    countStyle: .file
                ))
                .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)

            Button {
                isImporterPresented = true
            } label: {
                Label("Импортировать IPA", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Button(action: onOpenSettings) {
                HStack(spacing: 10) {
                    Image(systemName: certs.isCertHealthy ? "checkmark.shield.fill" : "person.crop.circle")
                        .foregroundStyle(certs.isCertHealthy ? Theme.success : Theme.primaryLight)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(certs.isLoggedIn ? certs.certStatusText : "Подключи Apple ID")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                        Text("Apple ID и подключение устройства — в настройках")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открывает настройки Apple ID и pairing")
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Theme.surfaceElevated, Theme.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Theme.primaryLight.opacity(0.22), lineWidth: 1)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField("Название или Bundle ID", text: $search)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Поиск приложений")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, search.isEmpty ? 16 : 4)
        .frame(minHeight: 52)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)) }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Тип IPA", selection: $segment) {
                ForEach(LibrarySegment.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(segment == .downloaded ? "Файлы IPA" : "Подписанные IPA")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("\(filteredList.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.primaryLight)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.primary.opacity(0.16), in: Capsule())
                Spacer()
                Menu {
                    Picker("Сортировка", selection: $sortBySize) {
                        Text("По названию").tag(false)
                        Text("Сначала большие").tag(true)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Сортировка приложений")
            }

            if isBusy {
                LibraryNotice(
                    title: "Выполняется операция",
                    message: signer.progressText.isEmpty ? installer.status : signer.progressText,
                    icon: "hourglass", color: Theme.primaryLight, isProgress: true
                )
            }
            if let errorMessage {
                LibraryNotice(title: "Не получилось", message: errorMessage, icon: "exclamationmark.circle", color: Theme.error)
                Button("Закрыть сообщение") { self.errorMessage = nil }
                    .font(.subheadline)
                    .frame(minHeight: 44)
            } else if let statusMessage {
                LibraryNotice(title: "Готово", message: statusMessage, icon: "checkmark.circle", color: Theme.success)
            }

            if filteredList.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredList) { file in
                        appCard(file)
                    }
                }
            }

            Label("Подписанный IPA ещё не означает установленное приложение.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: segment)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: search.isEmpty ? "square.and.arrow.down" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Theme.primaryLight)
                .frame(width: 80, height: 80)
                .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(search.isEmpty
                 ? (segment == .downloaded ? "Начни с первого IPA" : "Здесь будут подписанные IPA")
                 : "Ничего не найдено")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(search.isEmpty
                 ? (segment == .downloaded
                    ? "Добавь файл из приложения «Файлы».\nОн появится в твоей библиотеке."
                    : "Открой импортированный IPA и выбери «Подписать».")
                 : "Попробуй другое название или Bundle ID.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                if !search.isEmpty { search = "" }
                else if segment == .signed { segment = .downloaded }
                else { isImporterPresented = true }
            } label: {
                Text(search.isEmpty ? (segment == .signed ? "К импортированным" : "Выбрать IPA") : "Сбросить поиск")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryLight)
                    .frame(minHeight: 44)
            }
            .disabled(isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func appCard(_ file: LibraryIPA) -> some View {
        HStack(spacing: 4) {
            Button { path.append(file) } label: {
                LibraryRow(file: file, isSigned: segment == .signed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открывает сведения и действия с IPA")

            Menu {
                Button { path.append(file) } label: {
                    Label("Сведения", systemImage: "info.circle")
                }
                Button { Task { await sign(file) } } label: {
                    Label("Подписать", systemImage: "signature")
                }
                .disabled(isBusy)
                Button { Task { await install(file) } } label: {
                    Label("Подписать и установить", systemImage: "arrow.down.app")
                }
                .disabled(isBusy)
                Button { exportFile = file } label: {
                    Label("Экспортировать", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) { pendingDeletion = file } label: {
                    Label("Удалить IPA", systemImage: "trash")
                }
                .disabled(isBusy)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Действия: \(file.displayName)")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07)) }
    }

    private func reload() {
        importedFiles = LibraryIPALoader.load(in: "ImportedIPAs")
        signedFiles = LibraryIPALoader.load(in: "SignedIPAs")
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
            try await installer.signAndInstall(ipaURL: file.url)
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
    var isSigned = false

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(path: file.iconPath)
            VStack(alignment: .leading, spacing: 6) {
                Text(file.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(file.version.map { "Версия \($0)" } ?? "Версия не указана")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    Label(isSigned ? "Подписан" : "IPA", systemImage: isSigned ? "signature" : "shippingbox")
                        .foregroundStyle(isSigned ? Theme.success : Theme.primaryLight)
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppIconView: View {
    let path: String?
    var size: CGFloat = 58

    var body: some View {
        Group {
            if let path, let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.23)
                    .fill(Theme.primaryGradient)
                    .overlay {
                        Image(systemName: "app.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct LibraryBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.surfaceElevated.opacity(0.65), Theme.background, Theme.background],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct LibraryNotice: View {
    let title: String
    let message: String
    let icon: String
    let color: Color
    var isProgress = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isProgress {
                ProgressView().tint(color)
            } else {
                Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                Text(message).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var certs: CertificateStore
    let file: LibraryIPA
    let isSigned: Bool
    let busy: Bool
    let onSign: () -> Void
    let onSignAndInstall: () -> Void
    let onExport: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    AppIconView(path: file.iconPath, size: 96)
                        .shadow(color: Theme.primary.opacity(0.2), radius: 24, y: 12)
                    Text(file.displayName)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(file.version.map { "Версия \($0)" } ?? "Файл IPA")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Label(isSigned ? "Подписанный файл" : "Импортированный файл",
                          systemImage: isSigned ? "signature" : "shippingbox")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.primaryLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.primary.opacity(0.14), in: Capsule())
                }
                .padding(.vertical, 16)

                VStack(alignment: .leading, spacing: 18) {
                    Text("О приложении").font(.headline)
                    detail("Bundle ID", file.bundleID ?? "Не удалось прочитать")
                    Divider().overlay(.white.opacity(0.08))
                    detail("Размер", ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    Divider().overlay(.white.opacity(0.08))
                    detail("Файл", file.url.lastPathComponent)
                }
                .padding(20)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 12) {
                    Label("Подпись приложения", systemImage: "checkmark.shield")
                        .font(.headline)
                    Text(certs.appleID.isEmpty ? "Apple ID не подключён" : certs.appleID)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Text(certs.certName.isEmpty ? "Сертификат не выбран. Открой настройки для подключения." : certs.certName)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(certs.certStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(certs.isCertHealthy ? Theme.success : Theme.warning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))

                VStack(spacing: 12) {
                    Button(action: onSignAndInstall) {
                        Label(busy ? "Выполняется операция…" : "Подписать и установить",
                              systemImage: busy ? "hourglass" : "arrow.down.app")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .disabled(busy)

                    Button(action: onSign) {
                        Label("Только подписать", systemImage: "signature")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(Theme.primaryLight)
                    }
                    .disabled(busy)

                    Button(action: onExport) {
                        Label("Экспортировать IPA", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }

                    Text("Для установки нужны действующая сессия Apple ID, сертификат и подключение к устройству через pairing.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .opacity(busy ? 0.65 : 1)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(LibraryBackground())
        .navigationTitle("Сведения об IPA")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.subheadline).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
