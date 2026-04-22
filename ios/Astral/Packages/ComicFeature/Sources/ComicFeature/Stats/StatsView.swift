import SwiftUI
import SwiftData
import Core
import StatsUI

/// Comic tab — delegates to the shared stats surface. Historically the
/// entire unified stats layout was duplicated here and in
/// FanficStatsView; both are now ~10-line wrappers around
/// `SharedStatsView` in the `StatsUI` package.
struct StatsView: View {
    var body: some View { SharedStatsView() }
}

#Preview("Full Stats") {
    NavigationStack {
        StatsView()
            .modelContainer(.previewContainer(
                comics: PreviewMocks.sampleComics,
                comicChapters: PreviewMocks.comic1Chapters,
                fanfics: PreviewMocks.sampleFanfics,
                readingSessions: PreviewMocks.sampleReadingSessions
            ))
    }
}

#Preview("Empty Stats") {
    StatsView()
        .modelContainer(for: LocalComic.self, inMemory: true)
}
