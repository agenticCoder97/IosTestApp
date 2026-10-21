import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Core

public struct LibrarySettingsView<History: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var comics: [LocalComic]
    @Query private var fanfics: [LocalFanfic]
    @Query private var jobs: [LocalScrapeJob]
    @AppStorage("readerAlwaysShowControls") private var alwaysShowControls = false
    @AppStorage("comicOfflineLimit") private var comicOfflineLimit = 2
    @AppStorage("comicStorageLimitGB") private var comicStorageLimitGB = 5
    @AppStorage("companionURL") private var companionURL = ""
    @State private var address = ""
    @State private var exportedURL: URL?
    @State private var importing = false
    @State private var busy = false
    @State private var message: String?
    @State private var bytes: Int64 = 0
    private let history: History
    public init(@ViewBuilder history: () -> History) { self.history = history() }
    private var activeJobs: Bool { jobs.contains { ($0.jobType ?? "").hasPrefix("local") && ["running", "queued"].contains($0.status) } }

    public var body: some View {
        Form {
            Section("Reading") {
                Toggle("Always show reader controls", isOn: $alwaysShowControls)
                NavigationLink("Reading history") { history }
            }
            Section("Library and storage") {
                Stepper("Offline comics: \(comicOfflineLimit)", value: $comicOfflineLimit, in: 1...100)
                    .accessibilityIdentifier("settings.offlineComicLimit")
                Stepper("Comic storage budget: \(comicStorageLimitGB) GB", value: $comicStorageLimitGB, in: 1...100)
                    .accessibilityIdentifier("settings.comicStorageBudget")
                Text("A comic with any saved pages uses one offline slot. Library entries are unlimited. Lowering a limit keeps existing files and blocks new saves until there is room. Nothing is removed automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Manage saved content") { LibraryStorageView() }
                LabeledContent("Saved stories", value: "\(comics.count + fanfics.count)")
                LabeledContent("Content on this device", value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                Text("Use Storage to remove saved copies, or the story detail menu to delete a story. Export a backup before removing sole copies.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Export library backup", systemImage: "square.and.arrow.up") { export() }
                    .disabled(busy || activeJobs)
                Button("Restore library backup…", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(busy || activeJobs || LibraryBackupService.hasPendingRestore)
                if LibraryBackupService.hasPendingRestore {
                    Text("Restore is ready. Close Astral and reopen it to apply. Your current library is kept as a recovery copy.")
                        .foregroundStyle(.secondary)
                }
                Text("Backups include the database, saved content, bookmarks, reading positions and preferences. Restore replaces this device's collection on next launch. Use a backup from this version of Astral.")
                    .font(.footnote).foregroundStyle(.secondary)
                if activeJobs { Text("Wait for imports to finish before backing up or restoring.").font(.footnote) }
            }
            Section("Optional companion") {
                Text("Source imports and saved content run on this device. A companion is only for accessing an existing legacy collection. Source websites may require you to open Add and complete their normal browser verification.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("http://your-mac:8000", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityLabel("Companion address")
                Button("Save address") {
                    let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty { companionURL = ""; message = "Companion disabled."; return }
                    guard let url = URL(string: value), ["http", "https"].contains(url.scheme), url.host != nil,
                          url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                          url.path.isEmpty || url.path == "/" else {
                        message = "Enter a server origin, for example http://your-mac:8000."; return
                    }
                    companionURL = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    message = "Companion address saved."
                }
                if !companionURL.isEmpty { Button("Disconnect companion", role: .destructive) { companionURL = ""; address = "" } }
            }
            if busy { Section { ProgressView("Preparing backup…") } }
        }
        .navigationTitle("Settings")
        .onAppear { address = companionURL; updateSize() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, UTType(filenameExtension: "astralbackup") ?? .package]) { result in
            do {
                let url = try result.get()
                try modelContext.save()
                try LibraryBackupService.stageRestore(from: url)
                message = "Backup verified. Close Astral and reopen it to restore."
            } catch { message = error.localizedDescription }
        }
        .sheet(item: Binding(get: { exportedURL.map(ExportURL.init) }, set: { exportedURL = $0?.url })) { item in
            BackupExportPicker(url: item.url)
        }
        .alert("Library", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
    private func export() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try modelContext.save()
                exportedURL = try LibraryBackupService.create()
            } catch { message = error.localizedDescription }
        }
    }
    private func updateSize() {
        let files = FileManager.default.enumerator(at: .documentsDirectory, includingPropertiesForKeys: [.fileSizeKey])
        bytes = (files?.allObjects as? [URL] ?? []).reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

private struct ExportURL: Identifiable { let url: URL; var id: URL { url } }
private struct BackupExportPicker: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

public struct LibraryRecoveryView: View {
    let message: String
    let retry: () -> Void
    @State private var importing = false
    @State private var result: String?
    public init(message: String, retry: @escaping () -> Void) { self.message = message; self.retry = retry }
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "books.vertical").font(.largeTitle)
                Text("Your library could not be opened").font(.title2.bold())
                Text("Your database and saved content have been preserved. You can retry or restore a verified backup.")
                Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Try again", action: retry).buttonStyle(.borderedProminent)
                Button("Restore a backup…") { importing = true }
                if let result { Text(result).font(.callout) }
            }
            .padding(24).navigationTitle("Library recovery")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, UTType(filenameExtension: "astralbackup") ?? .package]) { response in
                do { try LibraryBackupService.stageRestore(from: response.get()); retry() }
                catch { result = error.localizedDescription }
            }
        }
    }
}
