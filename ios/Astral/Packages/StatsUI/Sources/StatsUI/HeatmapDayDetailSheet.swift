import SwiftUI
import Core
import DesignSystem

/// AST-68 — sheet presented when a user taps a non-empty heatmap cell.
/// Lists the reading sessions for that day with story title, chapters
/// opened, and session duration (when `endedAt` was recorded).
struct HeatmapDayDetailSheet: View {
    let day: Date
    let aggregates: StatsAggregates

    @Environment(\.dismiss) private var dismiss

    private var rows: [StatsAggregates.DaySessionRow] {
        aggregates.sessionsOn(day: day)
    }

    private var dayLabel: String {
        day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summaryCard

                    if rows.isEmpty {
                        Text("No reading on this day.")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(AstralColors.background)
            .navigationTitle(dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AstralColors.gold)
                }
            }
        }
    }

    private var summaryCard: some View {
        let totalChapters = rows.reduce(0) { $0 + $1.chaptersRead }
        let totalDuration = rows.compactMap { $0.duration }.reduce(0, +)
        return HStack(spacing: 12) {
            miniStat(value: "\(rows.count)", label: "Sessions")
            miniStat(value: "\(totalChapters)", label: "Chapters")
            miniStat(
                value: totalDuration > 0
                    ? StatsFormat.shortDuration(totalDuration)
                    : "—",
                label: "Time"
            )
        }
        .padding(12)
        .astralCard()
    }

    private func rowView(_ row: StatsAggregates.DaySessionRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.contentType == "comic" ? "book.closed.fill" : "scroll.fill")
                .font(.system(size: 16))
                .foregroundStyle(AstralColors.gold)
                .frame(width: 28, height: 28)
                .background(AstralColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.startedAt.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AstralColors.muted)
                    Text("•").foregroundStyle(AstralColors.muted)
                    Text("\(row.chaptersRead) ch")
                        .font(.system(size: 10))
                        .foregroundStyle(AstralColors.muted)
                    if let d = row.duration, d > 0 {
                        Text("•").foregroundStyle(AstralColors.muted)
                        Text(StatsFormat.shortDuration(d))
                            .font(.system(size: 10))
                            .foregroundStyle(AstralColors.muted)
                    }
                }
            }
            Spacer()
            Text(row.contentType == "comic" ? "Comic" : "Fanfic")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AstralColors.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AstralColors.elevated)
                .clipShape(Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AstralColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AstralColors.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AstralColors.muted)
        }
        .frame(maxWidth: .infinity)
    }
}
