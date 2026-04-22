import SwiftUI
import SwiftData
import Core
import StatsUI

/// Fanfic tab — delegates to the shared stats surface. See
/// `StatsUI.SharedStatsView` for the unified implementation used by
/// both tabs.
struct FanficStatsView: View {
    var body: some View { SharedStatsView() }
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

#Preview("Empty Stats") {
    FanficStatsView()
        .modelContainer(for: LocalComic.self, inMemory: true)
}
