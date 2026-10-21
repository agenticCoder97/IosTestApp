import SwiftUI
import SwiftData
import Core

public struct LibraryStorageView: View {
    @Query(sort: \LocalComic.title) private var comics: [LocalComic]
    @Query(sort: \LocalFanfic.title) private var fanfics: [LocalFanfic]
    @Query private var jobs: [LocalScrapeJob]
    @AppStorage("comicOfflineLimit") private var comicOfflineLimit = 2
    @Environment(\.modelContext) private var context
    @State private var selectedComic: LocalComic?
    @State private var selectedFanfic: LocalFanfic?
    @State private var message: String?
    @State private var sizes: [UUID: Int64] = [:]
    public init() {}
    public var body: some View {
        List {
            Section {
                let saved = comics.filter { ($0.chapters ?? []).contains { $0.localPagesPath != nil } }.count
                LabeledContent("Offline comics", value: "\(saved) / \(comicOfflineLimit)")
                if saved > comicOfflineLimit { Text("Above your new limit. Remove saved pages to free slots; your current copies have been kept.").foregroundStyle(.secondary) }
                Text("Removing saved copies keeps story metadata, favourites, bookmarks and reading position. To read again, import the original file or fetch the story from its source. Export a backup first for copies you cannot replace.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Comics") {
                ForEach(comics) { story in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                        Text(sizes[story.id].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Calculating size…").font(.caption).foregroundStyle(.secondary)
                        Button("Remove saved pages…", role: .destructive) { selectedComic = story }
                            .disabled(!(story.chapters ?? []).contains { $0.localPagesPath != nil } || active(story.id))
                            .accessibilityIdentifier("storage.removeComic." + story.id.uuidString)
                        if active(story.id) { Text("Cancel the active import/download in Activity before removing pages.").font(.caption) }
                    }.padding(.vertical, 4)
                }
            }
            Section("Fan fiction") {
                ForEach(fanfics) { story in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                        Text("\((story.chapters ?? []).filter { $0.localTextPath != nil }.count) saved chapters").font(.caption).foregroundStyle(.secondary)
                        Button("Remove saved text…", role: .destructive) { selectedFanfic = story }
                            .disabled(!(story.chapters ?? []).contains { $0.localTextPath != nil } || active(story.id))
                            .accessibilityIdentifier("storage.removeFanfic." + story.id.uuidString)
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Storage")
        .onAppear { updateSizes() }
        .confirmationDialog("Remove saved content?", isPresented: Binding(get: { selectedComic != nil || selectedFanfic != nil }, set: { if !$0 { selectedComic = nil; selectedFanfic = nil } }), titleVisibility: .visible) {
            Button("Remove saved copies", role: .destructive) {
                do {
                    if let selectedComic { try LocalStorageService.removeComicCopies(selectedComic, context: context) }
                    if let selectedFanfic { try LocalStorageService.removeFanficCopies(selectedFanfic, context: context) }
                    updateSizes()
                } catch { message = error.localizedDescription }
                selectedComic = nil; selectedFanfic = nil
            }
        } message: { Text("Metadata and reading position remain. Content must be imported again to read offline.") }
        .alert("Storage", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
    private func active(_ id: UUID) -> Bool { jobs.contains { $0.storyId == id && ["running", "queued"].contains($0.status) && ($0.jobType ?? "").hasPrefix("local") } }
    private func updateSizes() {
        let ids = comics.map(\.id)
        Task {
            let measured = await Task.detached {
                Dictionary(uniqueKeysWithValues: ids.map { ($0, LocalStorageService.bytes(in: URL.documentsDirectory.appendingPathComponent("comics/\($0)"))) })
            }.value
            sizes = measured
        }
    }
}
