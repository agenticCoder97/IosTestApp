import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

/// Architecture fix #9: This view was missing from the original architecture doc.
/// The fanfic sidebar had no Scrapes section despite fanfic scraping being a core feature.
struct FanficScrapesView: View {
    @Query(sort: \LocalFanfic.title)
    private var fanfics: [LocalFanfic]

    @Query(
        filter: #Predicate<LocalScrapeJob> { $0.contentType == "fanfic" },
        sort: \LocalScrapeJob.createdAt,
        order: .reverse
    )
    private var jobs: [LocalScrapeJob]

    @Environment(\.modelContext) private var modelContext
    @State private var selectedJob: LocalScrapeJob?
    @State private var timeFilter: TimeFilter = .all

    private var filteredJobs: [LocalScrapeJob] {
        let cutoff = timeFilter.cutoffDate
        return jobs.filter { $0.createdAt >= cutoff }
    }

    var body: some View {
        ScrollView {
            // Time filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { timeFilter = filter }
                        } label: {
                            Text(filter.label)
                                .font(AstralTypography.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(timeFilter == filter ? AstralColors.gold.opacity(0.25) : AstralColors.elevated)
                                .foregroundStyle(timeFilter == filter ? AstralColors.gold : AstralColors.muted)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if filteredJobs.isEmpty {
                EmptyStateView(
                    icon: "arrow.down.circle",
                    title: "No Scrape Jobs",
                    message: timeFilter == .all
                        ? "Start a scrape from the browser to see progress here."
                        : "No jobs in this time range."
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(groupedFilteredJobs.keys.sorted(), id: \.self) { status in
                        Section {
                            ForEach(groupedFilteredJobs[status] ?? []) { job in
                                FanficScrapeJobRow(
                                    job: job,
                                    storyTitle: fanfics.first { $0.id == job.storyId }?.title
                                ) {
                                    selectedJob = job
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteScrapeJob(job)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text(status.capitalized)
                                .font(AstralTypography.captionMedium)
                                .foregroundStyle(AstralColors.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .background(AstralColors.background)
        .task {
            while !Task.isCancelled {
                await syncActiveJobs()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .sheet(item: $selectedJob) { job in
            FanficScrapeJobDetailView(
                job: job,
                fanfic: fanfics.first { $0.id == job.storyId }
            )
        }
    }

    private func syncActiveJobs() async {
        // Fetch all fanfic scrape jobs from backend and upsert into SwiftData
        do {
            let response: PaginatedResponse<ScrapeJobResponse> = try await APIClient.shared.request(
                .allScrapeJobs(page: 1, pageSize: 100)
            )
            let fanficJobs = response.items.filter { $0.contentType == "fanfic" }
            for dto in fanficJobs {
                if let existing = jobs.first(where: { $0.id == dto.id }) {
                    existing.status = dto.status
                    existing.chaptersScraped = dto.chaptersScraped
                    existing.chaptersFailed = dto.chaptersFailed
                    existing.totalChapters = dto.totalChapters
                    existing.completedAt = dto.completedAt
                    existing.errorMessage = dto.errorMessage
                    existing.currentStep = dto.currentStep
                    existing.lastErrorType = dto.lastErrorType
                    existing.startedAt = dto.startedAt
                } else {
                    let job = LocalScrapeJob(
                        id: dto.id,
                        contentType: dto.contentType,
                        storyId: dto.storyId,
                        status: dto.status,
                        chaptersScraped: dto.chaptersScraped,
                        chaptersFailed: dto.chaptersFailed,
                        totalChapters: dto.totalChapters,
                        createdAt: dto.createdAt,
                        completedAt: dto.completedAt
                    )
                    job.errorMessage = dto.errorMessage
                    job.currentStep = dto.currentStep
                    job.lastErrorType = dto.lastErrorType
                    job.startedAt = dto.startedAt
                    modelContext.insert(job)
                }
            }
            try? modelContext.save()

            // AST-12: assign fallback thumbnails for newly-completed fanfics with nil paths
            for job in fanficJobs where job.status == "complete" || job.status == "partial" {
                guard let fanfic = fanfics.first(where: { $0.id == job.storyId }),
                      fanfic.thumbnailPath == nil else { continue }
                if let dto: RandomThumbnailResponse = try? await APIClient.shared.request(.randomFanficThumbnail) {
                    fanfic.thumbnailPath = dto.path
                    AstralLogger.info("Assigned thumbnail \(dto.path) to fanfic \(fanfic.id)", context: "FanficScrapes")
                }
            }
            try? modelContext.save()
        } catch {
            AstralLogger.error("syncActiveJobs failed: \(error)", context: "FanficScrapes")
        }

        // Resolve story titles for jobs without a matching LocalFanfic
        let missingStoryJobs = jobs.filter { job in
            !fanfics.contains { $0.id == job.storyId }
        }
        for job in missingStoryJobs {
            guard let dto: FanficResponse = try? await APIClient.shared.request(.fanficDetail(id: job.storyId)) else { continue }
            guard dto.title != "Pending scrape..." else { continue }
            let fanfic = LocalFanfic(
                id: dto.id,
                title: dto.title,
                sourceKey: dto.sourceKey,
                summary: dto.summary,
                fandom: dto.fandom,
                rating: dto.rating,
                completionStatus: dto.completionStatus,
                wordCount: dto.wordCount,
                totalChapters: dto.totalChapters,
                seenTotalChapters: dto.totalChapters
            )
            modelContext.insert(fanfic)
        }
        try? modelContext.save()
    }

    private var groupedFilteredJobs: [String: [LocalScrapeJob]] {
        Dictionary(grouping: filteredJobs, by: \.status)
    }

    private func deleteScrapeJob(_ job: LocalScrapeJob) {
        modelContext.delete(job)
        try? modelContext.save()
    }
}

// MARK: - Previews

#Preview("All Job Statuses") {
    FanficScrapesView()
        .modelContainer(.previewContainer(scrapeJobs: PreviewMocks.fanficScrapeJobs))
}

#Preview("Empty State") {
    FanficScrapesView()
        .modelContainer(for: LocalScrapeJob.self, inMemory: true)
}

#Preview("Running Job Row") {
    let job = LocalScrapeJob(
        id: UUID(),
        contentType: "fanfic",
        storyId: PreviewMocks.fanfic1.id,
        status: "running",
        chaptersScraped: 14,
        chaptersFailed: 0,
        totalChapters: 30,
        sourceKey: "ao3",
        jobType: "initial",
        currentStep: "chapter_14"
    )
    return FanficScrapeJobRow(job: job, onSelect: {})
        .padding()
        .background(AstralColors.background)
}

#Preview("Partial + Failed Row") {
    let job = LocalScrapeJob(
        id: UUID(),
        contentType: "fanfic",
        storyId: PreviewMocks.fanfic1.id,
        status: "partial",
        chaptersScraped: 18,
        chaptersFailed: 3,
        totalChapters: 21,
        sourceKey: "ffnet",
        jobType: "retry",
        errorMessage: "ScraperError: Failed after 3 attempts: timeout",
        lastErrorType: "ScraperError"
    )
    return FanficScrapeJobRow(job: job, onSelect: {})
        .padding()
        .background(AstralColors.background)
}

struct FanficScrapeJobRow: View {
    let job: LocalScrapeJob
    var storyTitle: String? = nil
    let onSelect: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var retryRotation: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(storyTitle ?? job.sourceKey?.uppercased() ?? job.id.uuidString.prefix(8).description)
                        .font(AstralTypography.bodyMedium)
                        .foregroundStyle(AstralColors.white)
                        .lineLimit(1)
                    if let jobType = job.jobType, jobType != "initial" {
                        Text(jobType.capitalized)
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.gold)
                    }
                }
                if storyTitle != nil, let key = job.sourceKey {
                    Text(key.uppercased())
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                }

                if let total = job.totalChapters, total > 0 {
                    Text("\(job.chaptersScraped)/\(total) chapters")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                        .contentTransition(.numericText())
                        .animation(AstralAnimation.smooth, value: job.chaptersScraped)

                    ProgressBarView(
                        progress: Double(job.chaptersScraped) / Double(total)
                    )
                }

                if let step = job.currentStep, job.status == "running", step != "done" {
                    Text(step.replacingOccurrences(of: "_", with: " "))
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.gold)
                }

                if job.chaptersFailed > 0 {
                    Text("\(job.chaptersFailed) failed")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.error)
                }

                if let errType = job.lastErrorType, job.status != "complete" {
                    Text(errType)
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.error)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AstralColors.muted)

            if job.status == "partial" || job.status == "failed" {
                Button {
                    withAnimation(.linear(duration: 0.5)) {
                        retryRotation += 360
                    }
                    Task { await retryJob() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(retryRotation))
                        .foregroundStyle(AstralColors.gold)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(PressButtonStyle(scale: 0.85))
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case "running":
            ProgressView()
                .tint(AstralColors.gold)
        case "queued":
            Image(systemName: "clock.badge.questionmark")
                .foregroundStyle(AstralColors.muted)
        case "complete":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AstralColors.success)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        case "partial":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AstralColors.warning)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AstralColors.error)
        default:
            Image(systemName: "clock")
                .foregroundStyle(AstralColors.muted)
        }
    }

    private func retryJob() async {
        AstralLogger.info("retryJob tapped | job_id=\(job.id) status=\(job.status)", context: "FanficScrapes")
        do {
            let response: ScrapeJobResponse = try await APIClient.shared.request(.retryScrape(jobId: job.id))
            AstralLogger.info("retryJob success | new_job_id=\(response.id) status=\(response.status)", context: "FanficScrapes")
            let newJob = LocalScrapeJob(
                id: response.id,
                contentType: response.contentType,
                storyId: response.storyId,
                status: response.status,
                chaptersScraped: response.chaptersScraped,
                chaptersFailed: response.chaptersFailed,
                totalChapters: response.totalChapters,
                createdAt: response.createdAt,
                completedAt: response.completedAt,
                sourceUrl: response.sourceUrl,
                sourceKey: response.sourceKey,
                jobType: response.jobType,
                errorMessage: response.errorMessage,
                currentStep: response.currentStep,
                lastErrorType: response.lastErrorType,
                startedAt: response.startedAt
            )
            modelContext.insert(newJob)
            try? modelContext.save()
        } catch {
            AstralLogger.error("retryJob failed: \(error)", context: "FanficScrapes")
        }
    }
}

private struct FanficScrapeJobDetailView: View {
    let job: LocalScrapeJob
    let fanfic: LocalFanfic?

    @Environment(\.dismiss) private var dismiss
    @State private var logs: [ScrapeLogEntry] = []
    @State private var isLoadingLogs = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Header card ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fanfic?.title ?? "Unknown Fanfic")
                            .font(AstralTypography.title)
                            .foregroundStyle(AstralColors.white)

                        HStack(spacing: 8) {
                            StatusBadge(statusLabel, color: statusColor)
                            if let jobType = job.jobType {
                                StatusBadge(jobType.capitalized, color: AstralColors.muted)
                            }
                            if let total = job.totalChapters, total > 0 {
                                StatusBadge("\(job.chaptersScraped)/\(total) ch", color: AstralColors.muted)
                            }
                        }

                        if let errMsg = job.errorMessage {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AstralColors.error)
                                    .font(.caption)
                                Text(errMsg)
                                    .font(AstralTypography.caption)
                                    .foregroundStyle(AstralColors.error)
                            }
                        }
                    }
                    .padding(16)
                    .astralCard()

                    // ── Details ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        if let url = job.sourceUrl {
                            detailRow(label: "Source URL", value: url)
                        }
                        if let key = job.sourceKey {
                            detailRow(label: "Source", value: key.uppercased())
                        }
                        detailRow(label: "Job ID", value: job.id.uuidString)
                        detailRow(label: "Created", value: dateText(job.createdAt))
                        if let started = job.startedAt {
                            detailRow(label: "Started", value: dateText(started))
                        }
                        detailRow(label: "Completed", value: job.completedAt.map(dateText) ?? "In progress")
                        detailRow(label: "Chapters Scraped", value: "\(job.chaptersScraped)")
                        if job.chaptersFailed > 0 {
                            detailRow(label: "Chapters Failed", value: "\(job.chaptersFailed)")
                        }
                        if let errType = job.lastErrorType {
                            detailRow(label: "Last Error Type", value: errType)
                        }
                        if let step = job.currentStep {
                            detailRow(label: "Last Step", value: step)
                        }
                    }
                    .padding(16)
                    .astralCard()

                    // ── Log timeline ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Event Log")
                            .font(AstralTypography.captionMedium)
                            .foregroundStyle(AstralColors.muted)

                        if isLoadingLogs {
                            ProgressView()
                                .tint(AstralColors.gold)
                                .frame(maxWidth: .infinity)
                        } else if logs.isEmpty {
                            Text("No events recorded yet.")
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.muted)
                        } else {
                            ForEach(logs) { entry in
                                FanficScrapeLogRow(entry: entry)
                            }
                        }
                    }
                    .padding(16)
                    .astralCard()
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .background(AstralColors.background)
            .navigationTitle("Job Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AstralColors.gold)
                }
            }
            .task { await loadLogs() }
        }
    }

    private func loadLogs() async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        logs = (try? await APIClient.shared.request(.scrapeJobLogs(jobId: job.id))) ?? []
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)
            Text(value)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.body)
                .textSelection(.enabled)
        }
    }

    private var statusLabel: String { job.status.capitalized }

    private var statusColor: Color {
        switch job.status {
        case "running": AstralColors.gold
        case "queued": AstralColors.muted
        case "complete": AstralColors.success
        case "partial": AstralColors.warning
        case "failed": AstralColors.error
        default: AstralColors.muted
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct FanficScrapeLogRow: View {
    let entry: ScrapeLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: levelIcon)
                .foregroundStyle(levelColor)
                .font(.caption)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.step)
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(AstralColors.white)
                    if let ms = entry.durationMs {
                        Text("\(ms)ms")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                    }
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                }
                Text(entry.message)
                    .font(AstralTypography.caption)
                    .foregroundStyle(entry.level == "error" ? AstralColors.error : AstralColors.body)
                if let errType = entry.errorType {
                    Text(errType)
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.error)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var levelIcon: String {
        switch entry.level {
        case "error": "xmark.circle.fill"
        case "warning": "exclamationmark.triangle.fill"
        default: "checkmark.circle.fill"
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case "error": AstralColors.error
        case "warning": AstralColors.warning
        default: AstralColors.success
        }
    }
}
