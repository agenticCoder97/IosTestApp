import SwiftUI
import SwiftData
import Core

public struct LocalActivityView<Destination: View>: View {
    @Query(sort: \LocalScrapeJob.createdAt, order: .reverse) private var jobs: [LocalScrapeJob]
    @Environment(\.modelContext) private var modelContext
    private let contentType: String
    private let destination: (LocalScrapeJob) -> Destination
    private let retry: (LocalScrapeJob) -> Void
    @AppStorage("companion.lastError") private var companionError = ""
    @State private var message: String?
    public init(contentType: String, retry: @escaping (LocalScrapeJob) -> Void, @ViewBuilder destination: @escaping (LocalScrapeJob) -> Destination) {
        self.contentType = contentType; self.retry = retry; self.destination = destination
    }
    public var body: some View {
        List {
            Section {
                Text("Imports and downloads run while Astral is open. Interrupted work can be retried; saved chapters remain available.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !companionError.isEmpty && AppConfig.companionEnabled { Section("Companion unavailable") { Text(companionError).font(.callout) } }
            if jobs.filter({ $0.contentType == contentType }).isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "arrow.down.circle", description: Text("Add a story to see its import here."))
            }
            ForEach(jobs.filter { $0.contentType == contentType }) { job in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(job.sourceKey?.uppercased() ?? "Import").font(.headline)
                        Spacer()
                        Text(label(job.status)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let step = job.currentStep { Text(step).font(.callout) }
                    if job.status == "running" {
                        if let total = job.totalChapters, total > 0 { ProgressView(value: Double(job.chaptersScraped), total: Double(total)) }
                        else { ProgressView("Importing…") }
                    }
                    if let error = job.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    Text(job.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if ["completed", "complete"].contains(job.status) { NavigationLink("Open story") { destination(job) } }
                        if ["failed", "cancelled"].contains(job.status) {
                            if job.jobType == "local-download" { NavigationLink("Open story to retry download") { destination(job) } }
                            else { Button("Retry import") { retry(job) } }
                        }
                        if LocalOperationRegistry.shared.canCancel(job.id) {
                            Button("Cancel", role: .destructive) { LocalOperationRegistry.shared.cancel(job.id) }
                        } else if !["running", "queued"].contains(job.status) {
                            Button("Dismiss history") {
                                if !(job.jobType ?? "").hasPrefix("local") {
                                    var dismissed = UserDefaults.standard.stringArray(forKey: "companion.dismissedJobs") ?? []
                                    dismissed.append(job.id.uuidString)
                                    UserDefaults.standard.set(dismissed, forKey: "companion.dismissedJobs")
                                }
                                modelContext.delete(job)
                                do { try modelContext.save() } catch { modelContext.rollback(); message = error.localizedDescription }
                            }
                        }
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 8)
            }
        }
        .navigationTitle("Activity")
        .alert("Activity", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
    private func label(_ status: String) -> String {
        switch status { case "completed": "Ready to read"; case "running": "Importing"; case "cancelled": "Cancelled"; case "failed": "Needs attention"; default: status.capitalized }
    }
}
