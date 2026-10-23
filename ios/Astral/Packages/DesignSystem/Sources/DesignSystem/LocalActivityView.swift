import SwiftUI
import SwiftData
import Core

public struct LocalActivityView<Destination: View>: View {
    @Query(sort: \LocalScrapeJob.createdAt, order: .reverse) private var jobs: [LocalScrapeJob]
    @Environment(\.modelContext) private var modelContext
    private let contentType: String
    private let destination: (LocalScrapeJob) -> Destination
    private let retry: (LocalScrapeJob) -> Void
    private let storyTitle: (LocalScrapeJob) -> String?
    @AppStorage("companion.lastError") private var companionError = ""
    @State private var message: String?
    @State private var confirmClear = false

    public init(contentType: String,
                storyTitle: @escaping (LocalScrapeJob) -> String? = { _ in nil },
                retry: @escaping (LocalScrapeJob) -> Void,
                @ViewBuilder destination: @escaping (LocalScrapeJob) -> Destination) {
        self.contentType = contentType; self.storyTitle = storyTitle; self.retry = retry; self.destination = destination
    }

    private var mine: [LocalScrapeJob] { jobs.filter { $0.contentType == contentType } }

    /// Repeated unfinished attempts at the same source collapse to the latest
    /// one, and an attempt that a later successful run replaced is hidden.
    private var visible: [LocalScrapeJob] {
        var seen = Set<String>()
        let mine = mine
        return mine.filter { job in
            guard Self.isUnfinished(job) else { return true }
            let resolved = mine.contains {
                ["completed", "complete"].contains($0.status) && $0.jobType == job.jobType && $0.createdAt > job.createdAt
                    && ($0.storyId == job.storyId || ($0.sourceUrl != nil && $0.sourceUrl?.lowercased() == job.sourceUrl?.lowercased()))
            }
            return !resolved && seen.insert(Self.key(job)).inserted
        }
    }

    private static func key(_ job: LocalScrapeJob) -> String {
        (job.jobType ?? "") + "|" + (job.jobType == "local-download" ? job.storyId.uuidString : (job.sourceUrl?.lowercased() ?? job.storyId.uuidString))
    }

    public var body: some View {
        let visible = visible
        let active = visible.filter(Self.isActive)
        // Something the user stopped isn't a problem to fix; it stays with finished work.
        let attention = visible.filter { $0.status == "failed" }
        let done = visible.filter { !Self.isActive($0) && $0.status != "failed" }
        List {
            if !companionError.isEmpty && AppConfig.companionEnabled {
                Section("Companion unavailable") { Text(companionError).font(.callout) }
            }
            if visible.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "arrow.down.circle",
                                       description: Text("Imports and chapter saves appear here while they run and after they finish."))
                    .listRowBackground(Color.clear)
            }
            if !active.isEmpty {
                Section("In progress") { ForEach(active) { row($0) } }
            }
            if !attention.isEmpty {
                Section("Needs attention") { ForEach(attention) { row($0) } }
            }
            if !done.isEmpty {
                Section("Done") { ForEach(done) { row($0) } }
            }
            if !visible.isEmpty {
                Section {
                } footer: {
                    Text("Imports and saves run while Astral is open. Interrupted work can be retried; chapters already saved stay available.")
                }
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            if mine.contains(where: { !Self.isActive($0) }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { confirmClear = true }
                        .accessibilityHint("Removes finished items from Activity")
                }
            }
        }
        .confirmationDialog("Clear finished activity?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear finished", role: .destructive) {
                mine.filter { !Self.isActive($0) }.forEach(dismiss)
            }
        } message: {
            Text("Only the history is removed. Stories and saved chapters stay in your library.")
        }
        .alert("Activity", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ job: LocalScrapeJob) -> some View {
        if Self.isActive(job) {
            VStack(alignment: .leading, spacing: 8) {
                ActivityJobRow(job: job, title: title(for: job))
                if LocalOperationRegistry.shared.canCancel(job.id) {
                    Button("Cancel", role: .destructive) { LocalOperationRegistry.shared.cancel(job.id) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                        .padding(.leading, 40)
                }
            }
        } else if Self.isUnfinished(job) {
            VStack(alignment: .leading, spacing: 8) {
                ActivityJobRow(job: job, title: title(for: job))
                HStack(spacing: 16) {
                    if job.jobType == "local-download" {
                        NavigationLink("Open story to retry") { destination(job) }
                    } else if job.sourceUrl != nil {
                        Button("Try again") { retry(job) }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(AstralColors.gold)
                .padding(.leading, 40)
            }
            .swipeActions { Button("Remove", role: .destructive) { dismiss(job) } }
        } else {
            NavigationLink { destination(job) } label: {
                ActivityJobRow(job: job, title: title(for: job))
            }
            .swipeActions { Button("Remove", role: .destructive) { dismiss(job) } }
        }
    }

    /// The library's current title wins. Completed jobs usually store the title
    /// (or, for folder imports, the folder name) as their last step; running and
    /// failed jobs store progress text, so they fall back to the source link.
    private func title(for job: LocalScrapeJob) -> String {
        if let title = storyTitle(job), !title.isEmpty { return title }
        if ["completed", "complete"].contains(job.status), let step = job.currentStep, !step.isEmpty { return step }
        if let url = job.sourceUrl.flatMap(URL.init(string:)) {
            // FanFiction.net links end with a readable title slug.
            let slug = url.pathComponents.last { $0.count > 3 && $0.contains("-") }
            if let slug { return slug.replacingOccurrences(of: "-", with: " ") }
            return url.host().map { $0.replacingOccurrences(of: "www.", with: "") + url.path } ?? url.absoluteString
        }
        return "Story from \(SourceLabel.name(for: job.sourceKey))"
    }

    private func dismiss(_ job: LocalScrapeJob) {
        if !(job.jobType ?? "").hasPrefix("local") {
            var dismissed = UserDefaults.standard.stringArray(forKey: "companion.dismissedJobs") ?? []
            dismissed.append(job.id.uuidString)
            UserDefaults.standard.set(dismissed, forKey: "companion.dismissedJobs")
        }
        modelContext.delete(job)
        do { try modelContext.save() } catch { modelContext.rollback(); message = error.localizedDescription }
    }

    private static func isActive(_ job: LocalScrapeJob) -> Bool { ActivityState.isActive(job) }
    private static func isUnfinished(_ job: LocalScrapeJob) -> Bool { ActivityState.isUnfinished(job) }
}

private enum ActivityState {
    static func isActive(_ job: LocalScrapeJob) -> Bool { ["running", "queued"].contains(job.status) }
    static func isUnfinished(_ job: LocalScrapeJob) -> Bool { ["failed", "cancelled"].contains(job.status) }
}

// MARK: - Row

private struct ActivityJobRow: View {
    let job: LocalScrapeJob
    let title: String

    private var isDownload: Bool { job.jobType == "local-download" }
    private var source: String { SourceLabel.name(for: job.sourceKey) }
    private var total: Int? { job.totalChapters.flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AstralColors.white)
                    .lineLimit(2)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(AstralColors.body)
                if ActivityState.isActive(job) {
                    if let total { ProgressView(value: Double(job.chaptersScraped), total: Double(total)).tint(AstralColors.gold) }
                    else { ProgressView().controlSize(.small).tint(AstralColors.gold) }
                    if let step = job.currentStep { Text(step).font(.caption).foregroundStyle(AstralColors.muted) }
                } else if job.status == "failed", let error = job.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AstralColors.muted)
                        .lineLimit(3)
                }
                Text(job.completedAt ?? job.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(AstralColors.muted)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch job.status {
        case "failed": "exclamationmark.triangle.fill"
        case "cancelled": "xmark.circle"
        default:
            if isDownload { "arrow.down.circle.fill" }
            else if job.jobType == "local-file" { "folder.fill" }
            else { "square.and.arrow.down.fill" }
        }
    }

    private var tint: Color {
        switch job.status {
        case "failed": AstralColors.warning
        case "cancelled": AstralColors.muted
        case "running", "queued": AstralColors.gold
        default: AstralColors.success
        }
    }

    private var summary: String {
        let chapters = { (n: Int) in "\(n) chapter\(n == 1 ? "" : "s")" }
        switch (isDownload, job.status) {
        case (true, "running"), (true, "queued"):
            return "Saving for offline reading" + (total.map { " · \(job.chaptersScraped) of \($0)" } ?? "")
        case (true, "cancelled"):
            return "Saving stopped" + (total.map { " · \(job.chaptersScraped) of \($0) saved" } ?? "")
        case (true, "failed"):
            return "Some chapters couldn't be saved" + (total.map { " · \(job.chaptersScraped) of \($0) saved" } ?? "")
        case (true, _):
            return "Saved \(chapters(job.chaptersScraped)) for offline reading"
        case (false, "running"), (false, "queued"):
            return "Importing from \(source)"
        case (false, "cancelled"):
            return "Import from \(source) cancelled"
        case (false, "failed"):
            return "Import from \(source) didn't finish" + (total.map { " · \(job.chaptersScraped) of \($0) chapters" } ?? "")
        default:
            if job.jobType == "local-file" { return "Imported from Files" + (total.map { " · " + chapters($0) } ?? "") }
            return "Imported from \(source)" + (total.map { " · " + chapters($0) } ?? "")
        }
    }
}
