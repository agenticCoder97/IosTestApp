import SwiftUI
import SwiftData
import Charts
import Core
import DesignSystem

/// Unified reading-stats surface shared by both the Comic and Fanfic tabs.
/// ComicFeature's `StatsView` and FanficFeature's `FanficStatsView` are
/// now thin wrappers around this one view — the previous ~1700 lines of
/// copy-pasted rendering code have been consolidated here.
///
/// Adds (AST-66..69):
///   • Reading time card + weekly-minutes chart (AST-66)
///   • Tag/genre breakdown chart (AST-67)
///   • Heatmap day drill-down sheet (AST-68)
///   • Bookmark analytics section (AST-69)
public struct SharedStatsView: View {
    @Query(filter: #Predicate<LocalComic> { $0.status != "deleted" })
    private var comics: [LocalComic]

    @Query(filter: #Predicate<LocalFanfic> { $0.completionStatus != "deleted" })
    private var fanfics: [LocalFanfic]

    @Query private var bookmarks: [LocalBookmark]

    @Query(sort: \LocalReadingSession.startedAt, order: .reverse)
    private var sessions: [LocalReadingSession]

    @Query private var comicChapters: [LocalComicChapter]

    @State private var selectedDay: SelectedDay?

    public init() {}

    private var agg: StatsAggregates {
        StatsAggregates(
            comics: comics, fanfics: fanfics,
            comicChapters: comicChapters,
            sessions: sessions,
            bookmarks: bookmarks
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection.staggeredAppear(index: 0)
                heatmapSection.staggeredAppear(index: 1)
                backlogSection.staggeredAppear(index: 2)
                breakdownSection.staggeredAppear(index: 3)
                bookmarkAnalyticsSection.staggeredAppear(index: 4)
                timelineSection.staggeredAppear(index: 5)

                Spacer().frame(height: 100)
            }
            .padding(.top, 16)
        }
        .background(AstralColors.background)
        .sheet(item: $selectedDay) { day in
            HeatmapDayDetailSheet(day: day.date, aggregates: agg)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: — Hero (odometer + streak)

    private var heroSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading Stats")
                        .font(AstralTypography.title)
                        .foregroundStyle(AstralColors.white)
                    Text("\(comics.count + fanfics.count) stories in library")
                        .font(AstralTypography.caption)
                        .foregroundStyle(AstralColors.muted)
                }
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(agg.currentStreak > 0 ? AstralColors.gold : AstralColors.muted)
                    Text("\(agg.currentStreak)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AstralColors.white)
                        .contentTransition(.numericText())
                    Text("day streak")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AstralColors.muted)
                }
            }

            HStack(spacing: 12) {
                odometerCard(
                    value: StatsFormat.compactNumber(agg.totalWordsRead),
                    label: "Words Read",
                    icon: "text.word.spacing",
                    sublabel: agg.novelEquivalent >= 1 ? String(format: "%.1f novels", agg.novelEquivalent) : nil
                )
                odometerCard(
                    value: StatsFormat.compactNumber(agg.totalPagesViewed),
                    label: "Pages Viewed",
                    icon: "photo.on.rectangle",
                    sublabel: nil
                )
            }

            HStack(spacing: 12) {
                odometerCard(
                    value: "\(agg.totalChaptersRead)",
                    label: "Chapters Read",
                    icon: "book.pages",
                    sublabel: nil
                )
                odometerCard(
                    value: "\(agg.longestStreak)",
                    label: "Best Streak",
                    icon: "trophy.fill",
                    sublabel: agg.longestStreak > 0 ? "days" : nil
                )
            }

            // AST-66 — reading time row
            HStack(spacing: 12) {
                odometerCard(
                    value: StatsFormat.duration(agg.totalReadingSeconds),
                    label: "Time Read",
                    icon: "clock.fill",
                    sublabel: agg.closedSessions.isEmpty ? nil
                        : "\(agg.closedSessions.count) sessions"
                )
                odometerCard(
                    value: agg.closedSessions.isEmpty
                        ? "—"
                        : StatsFormat.shortDuration(agg.averageSessionSeconds),
                    label: "Avg Session",
                    icon: "timer",
                    sublabel: nil
                )
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    private func odometerCard(value: String, label: String, icon: String, sublabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AstralColors.gold)
                Text(label)
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AstralColors.white)
                .contentTransition(.numericText())
                .animation(AstralAnimation.smooth, value: value)
            if let sublabel {
                Text(sublabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AstralColors.gold.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AstralColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: — Activity heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Activity", icon: "calendar")

            let heatmap = buildHeatmap()

            HStack(alignment: .top, spacing: 3) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(["", "M", "", "W", "", "F", ""], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 8))
                            .foregroundStyle(AstralColors.muted)
                            .frame(height: 11)
                    }
                }
                .frame(width: 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(0..<26, id: \.self) { week in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { day in
                                    let index = week * 7 + day
                                    let cell = index < heatmap.count ? heatmap[index] : nil
                                    HeatmapCell(
                                        count: cell?.count ?? 0,
                                        date: cell?.date,
                                        onTap: { date in
                                            selectedDay = SelectedDay(date: date)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // legend
            HStack(spacing: 4) {
                Text("Less").font(.system(size: 9)).foregroundStyle(AstralColors.muted)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapLevelColor(level))
                        .frame(width: 11, height: 11)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(AstralColors.muted)
                Spacer()
                Text("\(sessions.count) sessions")
                    .font(.system(size: 10))
                    .foregroundStyle(AstralColors.muted)
            }

            if !sessions.isEmpty {
                weeklySessionsChart
            }

            // AST-66 — weekly minutes
            let weekly = agg.weeklyReadingMinutes(weeks: 12)
            if weekly.contains(where: { $0.minutes > 0 }) {
                Divider().background(AstralColors.border)
                Text("Minutes Read / Week")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)
                Chart(weekly) { item in
                    BarMark(
                        x: .value("Week", item.label),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(AstralColors.gold.gradient)
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AstralColors.border)
                        AxisValueLabel().foregroundStyle(AstralColors.muted)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(AstralColors.muted)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    private struct HeatmapCellData {
        let date: Date
        let count: Int
    }

    private func buildHeatmap() -> [HeatmapCellData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todayWeekday = calendar.component(.weekday, from: today)
        let totalDays = 26 * 7
        let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1) + (6 - (todayWeekday - 1)), to: today)!

        var counts = Array(repeating: 0, count: totalDays)
        for session in sessions {
            let sessionDay = calendar.startOfDay(for: session.startedAt)
            let diff = calendar.dateComponents([.day], from: startDate, to: sessionDay).day ?? -1
            if diff >= 0 && diff < totalDays {
                counts[diff] += 1
            }
        }
        return (0..<totalDays).map { idx in
            let date = calendar.date(byAdding: .day, value: idx, to: startDate)!
            return HeatmapCellData(date: date, count: counts[idx])
        }
    }

    fileprivate static func heatmapColor(for count: Int) -> Color {
        switch count {
        case 0:  AstralColors.elevated
        case 1:  AstralColors.gold.opacity(0.25)
        case 2:  AstralColors.gold.opacity(0.45)
        case 3:  AstralColors.gold.opacity(0.65)
        default: AstralColors.gold.opacity(0.9)
        }
    }

    private func heatmapLevelColor(_ level: Int) -> Color {
        switch level {
        case 0:  AstralColors.elevated
        case 1:  AstralColors.gold.opacity(0.25)
        case 2:  AstralColors.gold.opacity(0.45)
        case 3:  AstralColors.gold.opacity(0.65)
        default: AstralColors.gold.opacity(0.9)
        }
    }

    private var weeklySessionsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 Days")
                .font(AstralTypography.captionMedium)
                .foregroundStyle(AstralColors.muted)

            let weekData = buildWeekData()
            Chart(weekData, id: \.day) { item in
                BarMark(
                    x: .value("Day", item.label),
                    y: .value("Sessions", item.count)
                )
                .foregroundStyle(AstralColors.gold.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(AstralColors.border)
                    AxisValueLabel().foregroundStyle(AstralColors.muted)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(AstralColors.muted)
                }
            }
            .frame(height: 120)
        }
    }

    private struct DayData {
        let day: Date
        let label: String
        let count: Int
    }

    private func buildWeekData() -> [DayData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let count = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }.count
            return DayData(day: date, label: formatter.string(from: date), count: count)
        }
    }

    // MARK: — Backlog dashboard (unchanged logic)

    private var backlogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Library Overview", icon: "books.vertical")

            let tiers = backlogTiers
            GeometryReader { geometry in
                let totalCount = max(1, tiers.reduce(0) { $0 + $1.count })
                HStack(spacing: 2) {
                    ForEach(tiers) { tier in
                        if tier.count > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(tier.color)
                                .frame(width: max(4, geometry.size.width * CGFloat(tier.count) / CGFloat(totalCount)))
                        }
                    }
                }
            }
            .frame(height: 24)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(tiers) { tier in
                    HStack(spacing: 6) {
                        Circle().fill(tier.color).frame(width: 8, height: 8)
                        Text(tier.name)
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.body)
                        Spacer()
                        Text("\(tier.count)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AstralColors.white)
                    }
                }
            }

            Divider().background(AstralColors.border)

            let almostDone = closestToFinishing
            if !almostDone.isEmpty {
                Text("Almost Done")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)
                ForEach(almostDone, id: \.title) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(AstralColors.gold)
                        Text(item.title)
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.white)
                            .lineLimit(1)
                        Spacer()
                        Text(item.remaining)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AstralColors.gold)
                    }
                }
            }

            let velocity = completionVelocity
            if !velocity.isEmpty {
                Divider().background(AstralColors.border)
                Text("Completions by Month")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)

                Chart(velocity, id: \.month) { item in
                    LineMark(x: .value("Month", item.label), y: .value("Count", item.count))
                        .foregroundStyle(AstralColors.success)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Month", item.label), y: .value("Count", item.count))
                        .foregroundStyle(AstralColors.success)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AstralColors.border)
                        AxisValueLabel().foregroundStyle(AstralColors.muted)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(AstralColors.muted)
                    }
                }
                .frame(height: 100)
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    private struct BacklogTier: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
        let color: Color
    }

    private var backlogTiers: [BacklogTier] {
        let allStories: [(progress: Double, lastRead: Date?, totalChapters: Int, completionStatus: String, lastReadChapterNumber: Int)] =
            comics.map { (
                progress: $0.progressPercent,
                lastRead: $0.lastReadAt,
                totalChapters: $0.totalChapters,
                completionStatus: $0.status,
                lastReadChapterNumber: $0.lastReadChapterNumber
            ) } +
            fanfics.map { (
                progress: $0.progressPercent,
                lastRead: $0.lastReadAt,
                totalChapters: $0.totalChapters,
                completionStatus: $0.completionStatus,
                lastReadChapterNumber: Int($0.lastReadChapterNumber ?? 0)
            ) }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        var notStarted = 0, inProgress = 0, caughtUp = 0, completed = 0, stale = 0

        for s in allStories {
            if s.progress >= 1.0 {
                completed += 1
            } else if s.progress == 0 {
                notStarted += 1
            } else if s.lastReadChapterNumber >= s.totalChapters && s.totalChapters > 0 {
                caughtUp += 1
            } else if let lr = s.lastRead, lr < thirtyDaysAgo {
                stale += 1
            } else {
                inProgress += 1
            }
        }

        return [
            BacklogTier(name: "Completed", count: completed, color: AstralColors.success),
            BacklogTier(name: "Caught Up", count: caughtUp, color: AstralColors.gold),
            BacklogTier(name: "In Progress", count: inProgress, color: Color(hex: 0x5C9DFF)),
            BacklogTier(name: "Not Started", count: notStarted, color: AstralColors.muted),
            BacklogTier(name: "Stale (30d+)", count: stale, color: AstralColors.error.opacity(0.7)),
        ]
    }

    private struct AlmostDoneItem {
        let title: String
        let remaining: String
        let icon: String
    }

    private var closestToFinishing: [AlmostDoneItem] {
        let comicItems: [AlmostDoneItem] = comics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 && $0.totalChapters > 0 }
            .sorted { $0.progressPercent > $1.progressPercent }
            .prefix(3)
            .map { AlmostDoneItem(
                title: $0.title,
                remaining: "\($0.totalChapters - $0.lastReadChapterNumber) ch left",
                icon: "book.closed.fill"
            ) }

        let fanficItems: [AlmostDoneItem] = fanfics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 && $0.totalChapters > 0 }
            .sorted { $0.progressPercent > $1.progressPercent }
            .prefix(3)
            .map { AlmostDoneItem(
                title: $0.title,
                remaining: "\($0.totalChapters - Int($0.lastReadChapterNumber ?? 0)) ch left",
                icon: "scroll.fill"
            ) }

        return (comicItems + fanficItems)
            .sorted { left, right in
                let lNum = Int(left.remaining.prefix(while: { $0.isNumber })) ?? 999
                let rNum = Int(right.remaining.prefix(while: { $0.isNumber })) ?? 999
                return lNum < rNum
            }
            .prefix(3)
            .map { $0 }
    }

    private struct VelocityData {
        let month: Date
        let label: String
        let count: Int
    }

    private var completionVelocity: [VelocityData] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        let allCompleted: [Date] = comics.compactMap { $0.completedAt } + fanfics.compactMap { $0.completedAt }
        guard !allCompleted.isEmpty else { return [] }

        return (0..<6).reversed().map { monthsAgo in
            let month = calendar.date(byAdding: .month, value: -monthsAgo, to: .now)!
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            let count = allCompleted.filter { $0 >= monthStart && $0 < nextMonth }.count
            return VelocityData(month: monthStart, label: formatter.string(from: monthStart), count: count)
        }
    }

    // MARK: — Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Breakdown", icon: "chart.pie")

            let comicCount = comics.count
            let fanficCount = fanfics.count
            if comicCount + fanficCount > 0 {
                HStack(spacing: 12) {
                    splitBadge("Comics", count: comicCount, icon: "book.closed.fill", color: Color(hex: 0x5C9DFF))
                    splitBadge("Fanfic", count: fanficCount, icon: "scroll.fill", color: AstralColors.gold)
                }
            }

            let sources = sourceDistribution
            if !sources.isEmpty {
                Divider().background(AstralColors.border)
                Text("By Source")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)
                Chart(sources, id: \.name) { source in
                    BarMark(x: .value("Count", source.count), y: .value("Source", source.name))
                        .foregroundStyle(source.color.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(source.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AstralColors.muted)
                        }
                }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(AstralColors.body) } }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(sources.count, 1)) * 32)
            }

            let fandoms = fandomDistribution
            if !fandoms.isEmpty {
                Divider().background(AstralColors.border)
                Text("Top Fandoms")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)
                Chart(fandoms, id: \.name) { fandom in
                    BarMark(x: .value("Count", fandom.count), y: .value("Fandom", fandom.name))
                        .foregroundStyle(AstralColors.gold.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(fandom.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AstralColors.muted)
                        }
                }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(AstralColors.body) } }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(fandoms.count, 1)) * 32)
            }

            // AST-67 — top tags
            let tags = agg.topTags(limit: 12)
            if !tags.isEmpty {
                Divider().background(AstralColors.border)
                Text("Top Tags")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)
                Chart(tags) { tag in
                    BarMark(x: .value("Count", tag.count), y: .value("Tag", tag.tag))
                        .foregroundStyle(Color(hex: 0xA78BDA).gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(tag.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AstralColors.muted)
                        }
                }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(AstralColors.body) } }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(tags.count) * 28)
            }

            let ratings = ratingDistribution
            if !ratings.isEmpty {
                Divider().background(AstralColors.border)
                Text("Ratings")
                    .font(AstralTypography.captionMedium)
                    .foregroundStyle(AstralColors.muted)
                HStack(spacing: 8) {
                    ForEach(ratings, id: \.name) { rating in
                        VStack(spacing: 4) {
                            Text("\(rating.count)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AstralColors.white)
                            Text(rating.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(rating.color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(rating.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    private func splitBadge(_ label: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AstralColors.white)
                Text(label).font(.system(size: 11)).foregroundStyle(AstralColors.muted)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private struct DistributionItem {
        let name: String
        let count: Int
        let color: Color
    }

    private var sourceDistribution: [DistributionItem] {
        var counts: [String: Int] = [:]
        for comic in comics { counts[comic.sourceKey, default: 0] += 1 }
        for fanfic in fanfics { counts[fanfic.sourceKey, default: 0] += 1 }

        let sourceColors: [String: Color] = [
            "ao3": Color(hex: 0x990000),
            "ffnet": Color(hex: 0x5C9DFF),
            "nhentai": AstralColors.error,
            "toongod": AstralColors.success,
            "hentai20": AstralColors.warning,
        ]

        return counts
            .sorted { $0.value > $1.value }
            .map { DistributionItem(name: $0.key, count: $0.value, color: sourceColors[$0.key] ?? AstralColors.muted) }
    }

    private var fandomDistribution: [DistributionItem] {
        var counts: [String: Int] = [:]
        for fanfic in fanfics {
            if let fandom = fanfic.fandom, !fandom.isEmpty {
                counts[fandom, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { DistributionItem(name: $0.key, count: $0.value, color: AstralColors.gold) }
    }

    private var ratingDistribution: [DistributionItem] {
        var counts: [String: Int] = [:]
        for fanfic in fanfics {
            if let rating = fanfic.rating, !rating.isEmpty {
                let short: String
                switch rating.lowercased() {
                case let r where r.contains("general"): short = "G"
                case let r where r.contains("teen"): short = "T"
                case let r where r.contains("mature"): short = "M"
                case let r where r.contains("explicit"): short = "E"
                default: short = String(rating.prefix(3)).uppercased()
                }
                counts[short, default: 0] += 1
            }
        }
        let ratingColors: [String: Color] = [
            "G": AstralColors.success,
            "T": Color(hex: 0x5C9DFF),
            "M": AstralColors.warning,
            "E": AstralColors.error,
        ]
        let order = ["G", "T", "M", "E"]
        return counts
            .sorted { (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99) }
            .map { DistributionItem(name: $0.key, count: $0.value, color: ratingColors[$0.key] ?? AstralColors.muted) }
    }

    // MARK: — AST-69 Bookmark analytics

    @ViewBuilder
    private var bookmarkAnalyticsSection: some View {
        if bookmarks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Bookmarks", icon: "bookmark.fill")

                // summary row
                let libraryCount = max(1, comics.count + fanfics.count)
                HStack(spacing: 12) {
                    miniStat(value: "\(bookmarks.count)", label: "Bookmarks")
                    miniStat(value: "\(agg.storiesWithBookmarks)", label: "Stories")
                    miniStat(
                        value: "\(Int(Double(agg.storiesWithBookmarks) / Double(libraryCount) * 100))%",
                        label: "of Library"
                    )
                }

                // most-annotated
                let topStories = agg.mostBookmarkedStories(limit: 5)
                if !topStories.isEmpty {
                    Divider().background(AstralColors.border)
                    Text("Most Annotated")
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(AstralColors.muted)
                    ForEach(topStories) { story in
                        HStack(spacing: 8) {
                            Image(systemName: story.contentType == "comic" ? "book.closed.fill" : "scroll.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(AstralColors.gold)
                            Text(story.title)
                                .font(AstralTypography.caption)
                                .foregroundStyle(AstralColors.white)
                                .lineLimit(1)
                            Spacer()
                            Text("\(story.count)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AstralColors.gold)
                        }
                    }
                }

                // weekly activity
                let activity = agg.weeklyBookmarkActivity(weeks: 12)
                if activity.contains(where: { $0.count > 0 }) {
                    Divider().background(AstralColors.border)
                    Text("Bookmarking Activity")
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(AstralColors.muted)
                    Chart(activity) { item in
                        BarMark(
                            x: .value("Week", item.label),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(AstralColors.gold.opacity(0.8).gradient)
                        .cornerRadius(3)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AstralColors.border)
                            AxisValueLabel().foregroundStyle(AstralColors.muted)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(AstralColors.muted)
                        }
                    }
                    .frame(height: 110)
                }

                // highlights carousel
                let highlights = agg.topHighlights
                if !highlights.isEmpty {
                    Divider().background(AstralColors.border)
                    Text("Recent Highlights")
                        .font(AstralTypography.captionMedium)
                        .foregroundStyle(AstralColors.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(highlights) { bm in
                                HighlightCard(bookmark: bm)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(16)
            .astralCard()
            .padding(.horizontal, 16)
        }
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
        .padding(.vertical, 10)
        .background(AstralColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: — Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Timeline", icon: "clock.arrow.circlepath")

            let events = buildTimeline()
            if events.isEmpty {
                Text("No reading history yet")
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(events) { group in
                    HStack(spacing: 6) {
                        Text(group.monthLabel)
                            .font(AstralTypography.captionMedium)
                            .foregroundStyle(AstralColors.gold)
                        Text(group.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(AstralColors.muted)
                        Spacer()
                    }
                    .padding(.top, group.id == events.first?.id ? 0 : 4)

                    ForEach(group.events) { event in
                        HStack(spacing: 10) {
                            VStack(spacing: 0) {
                                Circle().fill(event.color).frame(width: 8, height: 8)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: event.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(event.color)
                                    Text(event.action)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(event.color)
                                }
                                Text(event.title)
                                    .font(AstralTypography.caption)
                                    .foregroundStyle(AstralColors.white)
                                    .lineLimit(1)
                                Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.system(size: 9))
                                    .foregroundStyle(AstralColors.muted)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    private struct TimelineEvent: Identifiable {
        let id = UUID()
        let title: String
        let action: String
        let date: Date
        let icon: String
        let color: Color
    }

    private struct TimelineGroup: Identifiable {
        let id = UUID()
        let monthLabel: String
        let summary: String
        let events: [TimelineEvent]
    }

    private func buildTimeline() -> [TimelineGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        var allEvents: [TimelineEvent] = []
        for comic in comics {
            allEvents.append(TimelineEvent(
                title: comic.title, action: "Added", date: comic.addedAt,
                icon: "plus.circle.fill", color: AstralColors.gold
            ))
            if let completed = comic.completedAt {
                allEvents.append(TimelineEvent(
                    title: comic.title, action: "Completed", date: completed,
                    icon: "checkmark.circle.fill", color: AstralColors.success
                ))
            }
        }
        for fanfic in fanfics {
            allEvents.append(TimelineEvent(
                title: fanfic.title, action: "Added", date: fanfic.addedAt,
                icon: "plus.circle.fill", color: AstralColors.gold
            ))
            if let completed = fanfic.completedAt {
                allEvents.append(TimelineEvent(
                    title: fanfic.title, action: "Completed", date: completed,
                    icon: "checkmark.circle.fill", color: AstralColors.success
                ))
            }
        }

        allEvents.sort { $0.date > $1.date }
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: .now)!
        let recentEvents = allEvents.filter { $0.date >= sixMonthsAgo }

        var grouped: [String: [TimelineEvent]] = [:]
        var monthOrder: [String] = []
        for event in recentEvents {
            let key = formatter.string(from: event.date)
            if grouped[key] == nil { monthOrder.append(key) }
            grouped[key, default: []].append(event)
        }

        return monthOrder.map { monthKey in
            let events = grouped[monthKey]!
            let added = events.filter { $0.action == "Added" }.count
            let completed = events.filter { $0.action == "Completed" }.count
            var parts: [String] = []
            if added > 0 { parts.append("\(added) added") }
            if completed > 0 { parts.append("\(completed) completed") }
            return TimelineGroup(
                monthLabel: monthKey,
                summary: parts.joined(separator: ", "),
                events: Array(events.prefix(8))
            )
        }
    }

    // MARK: — shared helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(AstralColors.gold)
            Text(title)
                .font(AstralTypography.titleSmall)
                .foregroundStyle(AstralColors.white)
        }
    }
}

// MARK: - Heatmap cell (AST-68: tappable)

private struct HeatmapCell: View {
    let count: Int
    let date: Date?
    let onTap: (Date) -> Void

    var body: some View {
        Button {
            if let date, count > 0 { onTap(date) }
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(SharedStatsView.heatmapColor(for: count))
                .frame(width: 11, height: 11)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}

// MARK: - Highlight carousel card (AST-69)

private struct HighlightCard: View {
    let bookmark: LocalBookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 10))
                    .foregroundStyle(AstralColors.gold)
                Text(bookmark.displayLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AstralColors.muted)
                    .lineLimit(1)
            }
            Text(bookmark.selectedText ?? "")
                .font(.system(size: 12))
                .foregroundStyle(AstralColors.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if let note = bookmark.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(AstralColors.body)
                    .italic()
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(AstralColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Selected day wrapper (AST-68)

private struct SelectedDay: Identifiable {
    let date: Date
    var id: Date { date }
}
