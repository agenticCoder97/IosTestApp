import SwiftUI
import SwiftData
import Core
import DesignSystem
import Networking

struct ComicScrapesView: View {
    @Query(
        filter: #Predicate<LocalScrapeJob> { $0.contentType == "comic" },
        sort: \LocalScrapeJob.createdAt,
        order: .reverse
    )
    private var jobs: [LocalScrapeJob]

    var body: some View {
        ScrollView {
            if jobs.isEmpty {
                EmptyStateView(
                    icon: "arrow.down.circle",
                    title: "No Scrape Jobs",
                    message: "Start a scrape from the browser to see progress here."
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(groupedJobs.keys.sorted(), id: \.self) { status in
                        Section {
                            ForEach(groupedJobs[status] ?? []) { job in
                                ScrapeJobRow(job: job)
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
    }

    private var groupedJobs: [String: [LocalScrapeJob]] {
        Dictionary(grouping: jobs, by: \.status)
    }
}

// MARK: - Previews

#Preview("All Job Statuses") {
    ComicScrapesView()
        .modelContainer(.previewContainer(scrapeJobs: PreviewMocks.comicScrapeJobs))
}

#Preview("Empty State") {
    ComicScrapesView()
        .modelContainer(for: LocalScrapeJob.self, inMemory: true)
}

#Preview("Running Job Row") {
    ScrapeJobRow(job: PreviewMocks.scrapeJobRunning)
        .padding()
        .background(AstralColors.background)
}

#Preview("Partial Job Row") {
    ScrapeJobRow(job: PreviewMocks.scrapeJobPartial)
        .padding()
        .background(AstralColors.background)
}

#Preview("Complete Job Row") {
    ScrapeJobRow(job: PreviewMocks.scrapeJobComplete)
        .padding()
        .background(AstralColors.background)
}

struct ScrapeJobRow: View {
    let job: LocalScrapeJob

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text("Job \(job.id.uuidString.prefix(8))")
                    .font(AstralTypography.bodyMedium)
                    .foregroundStyle(AstralColors.white)

                if let total = job.totalChapters, total > 0 {
                    Text("\(job.chaptersScraped)/\(total) chapters")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)

                    ProgressBarView(
                        progress: Double(job.chaptersScraped) / Double(total)
                    )
                }
            }

            Spacer()

            if job.status == "partial" || job.status == "failed" {
                Button {
                    Task { await retryJob() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(AstralColors.gold)
                }
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case "running", "queued":
            ProgressView()
                .tint(AstralColors.gold)
        case "complete":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AstralColors.success)
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
        do {
            try await APIClient.shared.requestVoid(.retryScrape(jobId: job.id))
        } catch {
            // TODO: Handle error
        }
    }
}
