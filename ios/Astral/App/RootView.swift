import SwiftUI
import Core
import DesignSystem
import ComicFeature
import FanficFeature
import Networking

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("companionURL") private var companionURL = ""
    @State private var appState = AppState()
    @State private var showingIntro = !CommandLine.arguments.contains("--uitesting")
    @AppStorage("activeContentType") private var activeType = "fanfic"
    var body: some View {
        DebugShakeDetector {
            ZStack {
                ComicTabView(onSwitchTab: { activeType = "fanfic" })
                    .opacity(activeType == "comic" ? 1 : 0)
                    .zIndex(activeType == "comic" ? 1 : 0)
                    .allowsHitTesting(activeType == "comic")
                    .accessibilityHidden(activeType != "comic")
                FanficTabView(onSwitchTab: { activeType = "comic" })
                    .opacity(activeType == "fanfic" ? 1 : 0)
                    .zIndex(activeType == "fanfic" ? 1 : 0)
                    .allowsHitTesting(activeType == "fanfic")
                    .accessibilityHidden(activeType != "fanfic")
            }
        }
        .task(id: companionURL) {
            guard AppConfig.companionEnabled else { return }
            while !Task.isCancelled {
                if scenePhase == .active { await CompanionActivitySync.sync(context: modelContext) }
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .overlay(alignment: .bottom) { BookmarkUndoBanner().padding(.bottom, 80) }
        .environment(appState)
        .allowsHitTesting(!showingIntro)
        .accessibilityHidden(showingIntro)
        .overlay {
            if showingIntro {
                AstralIntroView {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        showingIntro = false
                    }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .alert("Library", isPresented: Binding(get: { StoryDeletionService.shared.errorMessage != nil }, set: { if !$0 { StoryDeletionService.shared.clearError() } })) {
            Button("OK") { StoryDeletionService.shared.clearError() }
        } message: { Text(StoryDeletionService.shared.errorMessage ?? "") }
    }
}
