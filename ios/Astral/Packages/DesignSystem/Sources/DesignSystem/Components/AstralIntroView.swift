import SwiftUI

/// A short launch film. Inactive scenes pause the same timeline instead of replaying it.
public struct AstralIntroView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = IntroPlaybackClock()
    @State private var completed = false
    private let onComplete: () -> Void
    private let previewTime: Double?

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        #if DEBUG
        previewTime = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--intro-time=") })
            .flatMap { Double($0.dropFirst("--intro-time=".count)) }
        #else
        previewTime = nil
        #endif
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || previewTime != nil || clock.resumedAt == nil)) { timeline in
            IntroArtwork(time: previewTime ?? (reduceMotion ? IntroMotion.duration : clock.elapsed(at: timeline.date)))
        }
        .background(AstralColors.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        // Once finished, the fading film must not catch the first tap meant for the library.
        .allowsHitTesting(!completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Astral")
        .accessibilityHint("Double-tap to skip")
        .accessibilityAction { finish() }
        .accessibilityIdentifier("launch.intro")
        .task(id: PlaybackState(scene: scenePhase, reducedMotion: reduceMotion)) {
            await updatePlayback()
        }
    }

    @MainActor
    private func updatePlayback() async {
        guard !completed, previewTime == nil else { return }
        guard scenePhase == .active else {
            clock.pause(at: Date())
            return
        }
        clock.resume(at: Date())
        let remaining = reduceMotion ? 0.25 : max(0, IntroMotion.duration - clock.elapsed(at: Date()))
        do { try await Task.sleep(for: .seconds(remaining)) }
        catch { return }
        guard !Task.isCancelled else { return }
        finish()
    }

    /// Tapping skips the rest of the film; frozen preview frames stay put.
    private func finish() {
        guard !completed, previewTime == nil else { return }
        completed = true
        onComplete()
    }

    private struct PlaybackState: Equatable {
        let scene: ScenePhase
        let reducedMotion: Bool
    }
}
