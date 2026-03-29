import SwiftUI
import SwiftData
import Charts
import Core
import DesignSystem

// MARK: - Unified Stats View (Fanfic tab)
// Identical to ComicFeature/StatsView — both tabs show the same unified stats.

struct FanficStatsView: View {
    @Query(filter: #Predicate<LocalComic> { $0.status != "deleted" })
    private var comics: [LocalComic]

    @Query(filter: #Predicate<LocalFanfic> { $0.completionStatus != "deleted" })
    private var fanfics: [LocalFanfic]

    @Query private var bookmarks: [LocalBookmark]
    @Query(sort: \LocalReadingSession.startedAt, order: .reverse)
    private var sessions: [LocalReadingSession]
    @Query private var comicChapters: [LocalComicChapter]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                    .staggeredAppear(index: 0)
                heatmapSection
                    .staggeredAppear(index: 1)
                backlogSection
                    .staggeredAppear(index: 2)
                breakdownSection
                    .staggeredAppear(index: 3)
                timelineSection
                    .staggeredAppear(index: 4)

                Spacer().frame(height: 100)
            }
            .padding(.top, 16)
        }
        .background(AstralColors.background)
    }

    // MARK: - Computed Stats

    private var totalWordsRead: Int {
        fanfics.reduce(0) { $0 + $1.estimatedWordsRead }
    }

    private var totalPagesViewed: Int {
        comics.reduce(0) { total, comic in
            let readChapters = comicChapters.filter { ch in
                ch.comicId == comic.id && ch.chapterNumber <= Double(comic.lastReadChapterNumber)
            }
            return total + readChapters.reduce(0) { $0 + $1.totalPages }
        }
    }

    private var novelEquivalent: Double {
        Double(totalWordsRead) / 80_000.0
    }

    private var currentStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: .now)
        let todaySessions = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: checkDate) }
        if todaySessions.isEmpty {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        while true {
            let dayStart = checkDate
            let hasSessions = sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: dayStart) }
            if hasSessions {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        return streak
    }

    private var longestStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let calendar = Calendar.current
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        let sortedDays = sessionDays.sorted()
        guard !sortedDays.isEmpty else { return 0 }
        var maxStreak = 1
        var current = 1
        for i in 1..<sortedDays.count {
            let diff = calendar.dateComponents([.day], from: sortedDays[i-1], to: sortedDays[i]).day ?? 0
            if diff == 1 { current += 1; maxStreak = max(maxStreak, current) } else { current = 1 }
        }
        return maxStreak
    }

    private var totalChaptersRead: Int {
        comics.reduce(0) { $0 + $1.lastReadChapterNumber } +
        fanfics.reduce(0) { $0 + $1.lastReadChapterNumber }
    }

    // MARK: - Hero Section

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
                        .foregroundStyle(currentStreak > 0 ? AstralColors.gold : AstralColors.muted)
                    Text("\(currentStreak)")
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
                    value: formattedWords(totalWordsRead), label: "Words Read",
                    icon: "text.word.spacing",
                    sublabel: novelEquivalent >= 1 ? String(format: "%.1f novels", novelEquivalent) : nil
                )
                odometerCard(
                    value: formattedNumber(totalPagesViewed), label: "Pages Viewed",
                    icon: "photo.on.rectangle", sublabel: nil
                )
            }
            HStack(spacing: 12) {
                odometerCard(
                    value: "\(totalChaptersRead)", label: "Chapters Read",
                    icon: "book.pages", sublabel: nil
                )
                odometerCard(
                    value: "\(longestStreak)", label: "Best Streak",
                    icon: "trophy.fill", sublabel: longestStreak > 0 ? "days" : nil
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

    // MARK: - Activity Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Activity", icon: "calendar")
            let heatmapData = buildHeatmapData()
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
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(index < heatmapData.count ? heatmapColor(for: heatmapData[index]) : AstralColors.elevated)
                                        .frame(width: 11, height: 11)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less").font(.system(size: 9)).foregroundStyle(AstralColors.muted)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapLevelColor(level))
                        .frame(width: 11, height: 11)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(AstralColors.muted)
                Spacer()
                Text("\(sessions.count) sessions").font(.system(size: 10)).foregroundStyle(AstralColors.muted)
            }
            if !sessions.isEmpty { weeklyBarChart }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    private func buildHeatmapData() -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todayWeekday = calendar.component(.weekday, from: today)
        let totalDays = 26 * 7
        let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1) + (6 - (todayWeekday - 1)), to: today)!
        var counts = Array(repeating: 0, count: totalDays)
        for session in sessions {
            let sessionDay = calendar.startOfDay(for: session.startedAt)
            let diff = calendar.dateComponents([.day], from: startDate, to: sessionDay).day ?? -1
            if diff >= 0 && diff < totalDays { counts[diff] += 1 }
        }
        return counts
    }

    private func heatmapColor(for count: Int) -> Color {
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

    private var weeklyBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 Days").font(AstralTypography.captionMedium).foregroundStyle(AstralColors.muted)
            let weekData = buildWeekData()
            Chart(weekData, id: \.day) { item in
                BarMark(x: .value("Day", item.label), y: .value("Sessions", item.count))
                    .foregroundStyle(AstralColors.gold.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AstralColors.border)
                    AxisValueLabel().foregroundStyle(AstralColors.muted)
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(AstralColors.muted) } }
            .frame(height: 120)
        }
    }

    private struct DayData { let day: Date; let label: String; let count: Int }

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

    // MARK: - Backlog Dashboard

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
                        Text(tier.name).font(AstralTypography.caption).foregroundStyle(AstralColors.body)
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
                Text("Almost Done").font(AstralTypography.captionMedium).foregroundStyle(AstralColors.muted)
                ForEach(almostDone, id: \.title) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon).font(.system(size: 12)).foregroundStyle(AstralColors.gold)
                        Text(item.title).font(AstralTypography.caption).foregroundStyle(AstralColors.white).lineLimit(1)
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
                Text("Completions by Month").font(AstralTypography.captionMedium).foregroundStyle(AstralColors.muted)
                Chart(velocity, id: \.month) { item in
                    LineMark(x: .value("Month", item.label), y: .value("Count", item.count))
                        .foregroundStyle(AstralColors.success)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Month", item.label), y: .value("Count", item.count))
                        .foregroundStyle(AstralColors.success)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(AstralColors.border)
                        AxisValueLabel().foregroundStyle(AstralColors.muted)
                    }
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(AstralColors.muted) } }
                .frame(height: 100)
            }
        }
        .padding(16)
        .astralCard()
        .padding(.horizontal, 16)
    }

    private struct BacklogTier: Identifiable {
        let id = UUID(); let name: String; let count: Int; let color: Color
    }

    private var backlogTiers: [BacklogTier] {
        let allStories: [(progress: Double, lastRead: Date?, totalChapters: Int, lastReadChapterNumber: Int)] =
            comics.map { ($0.progressPercent, $0.lastReadAt, $0.totalChapters, $0.lastReadChapterNumber) } +
            fanfics.map { ($0.progressPercent, $0.lastReadAt, $0.totalChapters, $0.lastReadChapterNumber) }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        var notStarted = 0, inProgress = 0, caughtUp = 0, completed = 0, stale = 0
        for s in allStories {
            if s.progress >= 1.0 { completed += 1 }
            else if s.progress == 0 { notStarted += 1 }
            else if s.lastReadChapterNumber >= s.totalChapters && s.totalChapters > 0 { caughtUp += 1 }
            else if let lr = s.lastRead, lr < thirtyDaysAgo { stale += 1 }
            else { inProgress += 1 }
        }
        return [
            BacklogTier(name: "Completed", count: completed, color: AstralColors.success),
            BacklogTier(name: "Caught Up", count: caughtUp, color: AstralColors.gold),
            BacklogTier(name: "In Progress", count: inProgress, color: Color(hex: 0x5C9DFF)),
            BacklogTier(name: "Not Started", count: notStarted, color: AstralColors.muted),
            BacklogTier(name: "Stale (30d+)", count: stale, color: AstralColors.error.opacity(0.7)),
        ]
    }

    private struct AlmostDoneItem { let title: String; let remaining: String; let icon: String }

    private var closestToFinishing: [AlmostDoneItem] {
        let comicItems: [AlmostDoneItem] = comics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 && $0.totalChapters > 0 }
            .sorted { $0.progressPercent > $1.progressPercent }
            .prefix(3)
            .map { AlmostDoneItem(title: $0.title, remaining: "\($0.totalChapters - $0.lastReadChapterNumber) ch left", icon: "book.closed.fill") }
        let fanficItems: [AlmostDoneItem] = fanfics
            .filter { $0.progressPercent > 0 && $0.progressPercent < 1.0 && $0.totalChapters > 0 }
            .sorted { $0.progressPercent > $1.progressPercent }
            .prefix(3)
            .map { AlmostDoneItem(title: $0.title, remaining: "\($0.totalChapters - $0.lastReadChapterNumber) ch left", icon: "scroll.fill") }
        return (comicItems + fanficItems)
            .sorted { Int($0.remaining.prefix(while: { $0.isNumber })) ?? 999 < Int($1.remaining.prefix(while: { $0.isNumber })) ?? 999 }
            .prefix(3).map { $0 }
    }

    private struct VelocityData { let month: Date; let label: String; let count: Int }

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

    // MARK: - Fandom & Source Breakdown

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
                Text("By Source").font(AstralTypography.captionMedium).foregroundStyle(AstralColors.muted)
                Chart(sources, id: \.name) { source in
                    BarMark(x: .value("Count", source.count), y: .value("Source", source.name))
                        .foregroundStyle(source.color.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(source.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(AstralColors.muted)
                        }
                }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(AstralColors.body) } }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(sources.count, 1)) * 32)
            }
            let fandoms = fandomDistribution
            if !fandoms.isEmpty {
                Divider().background(AstralColors.border)
                Text("Top Fandoms").font(AstralTypography.captionMedium).foregroundStyle(AstralColors.muted)
                Chart(fandoms, id: \.name) { fandom in
                    BarMark(x: .value("Count", fandom.count), y: .value("Fandom", fandom.name))
                        .foregroundStyle(AstralColors.gold.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(fandom.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(AstralColors.muted)
                        }
                }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(AstralColors.body) } }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(fandoms.count, 1)) * 32)
            }
            let ratings = ratingDistribution
            if !ratings.isEmpty {
                Divider().background(AstralColors.border)
                Text("Ratings").font(AstralTypography.captionMedium).foregroundStyle(AstralColors.muted)
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

    private struct DistributionItem { let name: String; let count: Int; let color: Color }

    private var sourceDistribution: [DistributionItem] {
        var counts: [String: Int] = [:]
        for comic in comics { counts[comic.sourceKey, default: 0] += 1 }
        for fanfic in fanfics { counts[fanfic.sourceKey, default: 0] += 1 }
        let sourceColors: [String: Color] = [
            "ao3": Color(hex: 0x990000), "ffnet": Color(hex: 0x5C9DFF),
            "nhentai": AstralColors.error, "toongod": AstralColors.success, "hentai20": AstralColors.warning,
        ]
        return counts.sorted { $0.value > $1.value }
            .map { DistributionItem(name: $0.key, count: $0.value, color: sourceColors[$0.key] ?? AstralColors.muted) }
    }

    private var fandomDistribution: [DistributionItem] {
        var counts: [String: Int] = [:]
        for fanfic in fanfics {
            if let fandom = fanfic.fandom, !fandom.isEmpty { counts[fandom, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(6)
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
                default: short = rating.prefix(3).uppercased()
                }
                counts[short, default: 0] += 1
            }
        }
        let ratingColors: [String: Color] = ["G": AstralColors.success, "T": Color(hex: 0x5C9DFF), "M": AstralColors.warning, "E": AstralColors.error]
        let order = ["G", "T", "M", "E"]
        return counts.sorted { (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99) }
            .map { DistributionItem(name: $0.key, count: $0.value, color: ratingColors[$0.key] ?? AstralColors.muted) }
    }

    // MARK: - Library Timeline

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
                        Text(group.monthLabel).font(AstralTypography.captionMedium).foregroundStyle(AstralColors.gold)
                        Text(group.summary).font(.system(size: 10)).foregroundStyle(AstralColors.muted)
                        Spacer()
                    }
                    .padding(.top, group.id == events.first?.id ? 0 : 4)

                    ForEach(group.events) { event in
                        HStack(spacing: 10) {
                            Circle().fill(event.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: event.icon).font(.system(size: 10)).foregroundStyle(event.color)
                                    Text(event.action).font(.system(size: 10, weight: .medium)).foregroundStyle(event.color)
                                }
                                Text(event.title).font(AstralTypography.caption).foregroundStyle(AstralColors.white).lineLimit(1)
                                Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.system(size: 9)).foregroundStyle(AstralColors.muted)
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
        let id = UUID(); let title: String; let action: String; let date: Date; let icon: String; let color: Color
    }

    private struct TimelineGroup: Identifiable {
        let id = UUID(); let monthLabel: String; let summary: String; let events: [TimelineEvent]
    }

    private func buildTimeline() -> [TimelineGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var allEvents: [TimelineEvent] = []
        for comic in comics {
            allEvents.append(TimelineEvent(title: comic.title, action: "Added", date: comic.addedAt, icon: "plus.circle.fill", color: AstralColors.gold))
            if let completed = comic.completedAt {
                allEvents.append(TimelineEvent(title: comic.title, action: "Completed", date: completed, icon: "checkmark.circle.fill", color: AstralColors.success))
            }
        }
        for fanfic in fanfics {
            allEvents.append(TimelineEvent(title: fanfic.title, action: "Added", date: fanfic.addedAt, icon: "plus.circle.fill", color: AstralColors.gold))
            if let completed = fanfic.completedAt {
                allEvents.append(TimelineEvent(title: fanfic.title, action: "Completed", date: completed, icon: "checkmark.circle.fill", color: AstralColors.success))
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
            return TimelineGroup(monthLabel: monthKey, summary: parts.joined(separator: ", "), events: Array(events.prefix(8)))
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(AstralColors.gold)
            Text(title).font(AstralTypography.titleSmall).foregroundStyle(AstralColors.white)
        }
    }

    private func formattedWords(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func formattedNumber(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

#Preview("Full Stats") {
    NavigationStack {
        FanficStatsView()
            .modelContainer(.previewContainer(
                comics: PreviewMocks.sampleComics,
                comicChapters: PreviewMocks.comic1Chapters,
                fanfics: PreviewMocks.sampleFanfics,
                readingSessions: PreviewMocks.sampleReadingSessions
            ))
    }
}
