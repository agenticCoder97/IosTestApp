# Astral UI/source inventory

Generated from the working tree on 2026-10-21. Source declarations and control locations; not a list of passed runtime checks. Read with [the review and plan](2026-10-21-app-review-and-rebuild-plan.md).

## ios/Astral/App/AppState.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/AppState.swift:3) `enum AppTab: String, CaseIterable {`
- [9](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/AppState.swift:9) `final class AppState {`
- [14](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/AppState.swift:14) `func toggleSidebar() {`
- [25](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/AppState.swift:25) `func closeSidebars() {`

## ios/Astral/App/RootView.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:8) `private enum WobbleBeat: CaseIterable {`
- [23](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:23) `private enum LandingTerminalState {`
- [37](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:37) `struct RootView: View {`
- [75](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:75) `private enum PhaseGeometry {`
- [92](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:92) `private struct MorphLandingView: View {`
- [201](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:201) `Button {`
- [210](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:210) `Button {`
- [367](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:367) `private func runAnimation(in size: CGSize) {`
- [381](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:381) `private func applyReducedMotionState() {`
- [413](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:413) `private func runPhase1(in size: CGSize) {`
- [452](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:452) `private func runPhase2(in size: CGSize) {`
- [499](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:499) `private func runPhase3(in size: CGSize) {`
- [538](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/RootView.swift:538) `private func runPhase4(in size: CGSize) {`

## ios/Astral/App/TabBarView.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/TabBarView.swift:4) `struct TabBarView: View {`
- [21](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/TabBarView.swift:21) `private func tabItem(tab: AppTab, icon: String, label: String) -> some View {`
- [23](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/App/TabBarView.swift:23) `return Button {`

## ios/Astral/AstralApp.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/AstralApp.swift:7) `class AstralAppDelegate: NSObject, UIApplicationDelegate {`
- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/AstralApp.swift:8) `func application(`
- [18](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/AstralApp.swift:18) `struct AstralApp: App {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:8) `struct ComicBrowserView: View {`
- [16](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:16) `Menu {`
- [18](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:18) `Button {`
- [54](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:54) `Button(action: viewModel.goBack) {`
- [60](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:60) `Button(action: viewModel.goForward) {`
- [66](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:66) `Button(action: viewModel.reload) {`
- [78](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:78) `TextField("Enter URL", text: $viewModel.addressBarText)`
- [91](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:91) `Button(action: {`
- [111](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:111) `Button {`
- [126](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:126) `.sheet(item: Binding(`
- [149](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:149) `final class ComicBrowserViewModel {`
- [179](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:179) `func navigateToAddress() {`
- [201](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:201) `func extractCookiesAndScrape() async -> LocalScrapeJob? {`
- [233](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:233) `private func submitAndHandle(_ request: ScrapeRequest) async -> LocalScrapeJob? {`
- [274](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:274) `func acceptMatch(modelContext: ModelContext) {`
- [299](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:299) `func declineMatch(modelContext: ModelContext) {`
- [318](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:318) `func showToast(_ toast: ScrapeToast) {`
- [326](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:326) `func evaluateCanScrape(url: URL?) {`
- [344](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:344) `func goBack() { webView?.goBack() }`
- [345](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:345) `func goForward() { webView?.goForward() }`
- [346](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:346) `func reload() { webView?.reload() }`
- [348](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:348) `func resetToSourceHome() {`
- [364](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:364) `struct ComicWebViewRepresentable: UIViewRepresentable {`
- [367](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:367) `func makeUIView(context: Context) -> WKWebView {`
- [409](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:409) `func updateUIView(_ webView: WKWebView, context: Context) {`
- [416](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:416) `func makeCoordinator() -> Coordinator {`
- [420](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:420) `class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {`
- [434](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:434) `func webView(`
- [458](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:458) `func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {`
- [488](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:488) `func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {`
- [495](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:495) `func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {`
- [503](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:503) `func webView(`
- [513](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:513) `func webView(`
- [522](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:522) `func webView(`
- [533](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:533) `func webView(`
- [545](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/ComicBrowserView.swift:545) `private struct MatchProposalIdentifiable: Identifiable {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift:8) `struct MangaDexMatchDialog: View {`
- [54](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift:54) `Button {`
- [66](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Browser/MangaDexMatchDialog.swift:66) `Button {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicSidebarView.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicSidebarView.swift:4) `struct ComicSidebarView: View {`
- [15](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicSidebarView.swift:15) `.onTapGesture {`
- [45](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicSidebarView.swift:45) `private func sidebarRow(_ section: ComicSection) -> some View {`
- [46](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicSidebarView.swift:46) `Button {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:5) `public struct ComicTabView: View {`
- [47](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:47) `Menu {`
- [48](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:48) `Button {`
- [53](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:53) `Button {`
- [76](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:76) `Button {`
- [89](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:89) `Button {`
- [100](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:100) `Button {`
- [125](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:125) `.sheet(isPresented: $showFilter) {`
- [137](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:137) `private func saveFilterPrefs() {`
- [146](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:146) `final class ComicNavigation {`
- [153](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:153) `func searchFor(_ term: String) {`
- [160](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:160) `private struct ComicNavigationKey: EnvironmentKey {`
- [171](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ComicTabView.swift:171) `enum ComicSection: String, CaseIterable {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift:5) `struct ComicCardView: View {`
- [10](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift:10) `private func thumbnailURL(_ path: String) -> URL? {`
- [136](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicCardView.swift:136) `Button {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:7) `struct ComicDetailView: View {`
- [22](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:22) `private enum DetailTab: String, CaseIterable {`
- [68](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:68) `private func titleOpacity(heroHeight: CGFloat) -> Double {`
- [125](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:125) `Button {`
- [139](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:139) `Button {`
- [161](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:161) `Button {`
- [191](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:191) `Button {`
- [221](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:221) `Button {`
- [248](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:248) `Button {`
- [261](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:261) `Button {`
- [283](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:283) `Button {`
- [316](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:316) `Button {`
- [330](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:330) `Button {`
- [360](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:360) `Button {`
- [391](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:391) `Button(role: .destructive) {`
- [428](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:428) `Menu {`
- [429](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:429) `Button(role: .destructive) {`
- [461](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:461) `.fullScreenCover(item: $selectedChapter) { chapter in`
- [472](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:472) `private func syncChapters() async {`
- [545](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:545) `private func metadataRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {`
- [560](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:560) `private func infoCell(label: String, value: String) -> some View {`
- [584](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:584) `private func thumbnailURL(_ path: String) -> URL? {`
- [589](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:589) `private func handleDownloadTap() {`
- [610](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:610) `private func addBookmark(for chapter: LocalComicChapter) {`
- [620](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:620) `private func archiveComic() {`
- [628](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:628) `private func unarchiveComic() {`
- [636](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:636) `private func deleteBookmark(_ bookmark: LocalBookmark) {`
- [644](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:644) `private struct ScrollOffsetKey: PreferenceKey {`
- [646](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:646) `static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {`
- [653](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:653) `private struct BookmarksSection: View {`
- [662](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:662) `Button {`
- [698](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:698) `Button {`
- [727](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:727) `private struct ComicChapterRow: View {`
- [796](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:796) `private func downloadStatusIcon(for chapter: LocalComicChapter) -> some View {`
- [815](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:815) `private func statusIcon(for status: String) -> some View {`
- [841](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:841) `private struct ContinueReadingButton<Destination: View>: View {`
- [846](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:846) `private enum ReadingState {`
- [869](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:869) `NavigationLink {`
- [887](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:887) `private func targetChapter(for state: ReadingState) -> LocalComicChapter {`
- [893](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:893) `private func iconName(for state: ReadingState) -> String {`
- [901](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:901) `private func label(for state: ReadingState) -> String {`
- [916](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:916) `private func backgroundColor(for state: ReadingState) -> Color {`
- [923](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift:923) `private func labelColor(for state: ReadingState) -> Color {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterPrefs.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterPrefs.swift:4) `struct ComicFilterPrefs: Codable {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterState.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterState.swift:5) `enum ComicSortOption: String, CaseIterable {`
- [14](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterState.swift:14) `final class ComicFilterState {`
- [32](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterState.swift:32) `func reset() {`
- [42](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterState.swift:42) `func load(from prefs: ComicFilterPrefs) {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterView.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterView.swift:5) `struct ComicFilterView: View {`
- [93](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterView.swift:93) `Button("Reset") {`
- [99](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterView.swift:99) `Button("Done") {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:7) `struct ComicLibraryView: View {`
- [133](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:133) `NavigationLink {`
- [141](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:141) `.contextMenu {`
- [143](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:143) `Button {`
- [149](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:149) `Button {`
- [155](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:155) `Button(role: .destructive) {`
- [204](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:204) `private func archiveComic(_ comic: LocalComic) {`
- [212](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:212) `private func unarchiveComic(_ comic: LocalComic) {`
- [223](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:223) `private struct ContinueReadingStrip: View {`
- [248](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:248) `private struct ContinueReadingCardLink: View {`
- [267](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:267) `NavigationLink {`
- [275](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift:275) `private struct ContinueReadingCard: View {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicSearchView.swift

- [6](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicSearchView.swift:6) `struct ComicSearchView: View {`
- [25](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicSearchView.swift:25) `private func names(from json: String?) -> [String] {`
- [35](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicSearchView.swift:35) `private enum MatchTier: Int, Comparable {`
- [47](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicSearchView.swift:47) `private func matchTier(for comic: LocalComic, query: String) -> MatchTier? {`
- [110](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicSearchView.swift:110) `NavigationLink {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift

- [9](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:9) `enum ReadingMode: String, CaseIterable {`
- [23](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:23) `enum ComicChapterPullTrigger {`
- [24](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:24) `static func shouldFire(progress: CGFloat, hasTriggered: Bool) -> Bool {`
- [29](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:29) `struct ComicReaderPageSource {`
- [48](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:48) `struct ComicReaderView: View {`
- [288](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:288) `.onTapGesture {`
- [295](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:295) `.sheet(isPresented: $showChapterList) {`
- [419](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:419) `.simultaneousGesture(`
- [453](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:453) `private func pagedReader(reversed: Bool) -> some View {`
- [460](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:460) `Button { goToPrevChapter() } label: {`
- [498](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:498) `Button { goToNextChapter() } label: {`
- [526](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:526) `.simultaneousGesture(`
- [532](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:532) `private func toggleHUD() {`
- [540](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:540) `private func setLandscape(_ landscape: Bool) {`
- [554](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:554) `Button { dismiss() } label: {`
- [585](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:585) `Button { showChapterList = true } label: {`
- [590](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:590) `Button {`
- [605](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:605) `Button {`
- [615](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:615) `Button {`
- [659](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:659) `Slider(`
- [684](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:684) `Button { goToPrevChapter() } label: {`
- [694](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:694) `Menu {`
- [696](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:696) `Button("Page \(idx + 1)") {`
- [724](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:724) `Button { goToNextChapter() } label: {`
- [752](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:752) `Button {`
- [790](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:790) `Stepper(value: Binding(`
- [813](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:813) `Slider(value: $brightnessOverlay, in: 0...0.75)`
- [830](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:830) `Toggle("", isOn: $autoScrollActive)`
- [839](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:839) `Slider(value: $autoScrollSpeed, in: 0.5...5.0, step: 0.5)`
- [856](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:856) `Toggle("", isOn: $forceLandscape)`
- [872](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:872) `private func prevPage() {`
- [876](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:876) `private func nextPage() {`
- [880](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:880) `private func goToPrevChapter() {`
- [889](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:889) `private func goToNextChapter() {`
- [898](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:898) `private func chapterTransitionPage(direction: String, icon: String) -> some View {`
- [920](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:920) `private func bookmarkCurrentChapter() {`
- [945](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:945) `private func applyPageSkip(_ allPages: [PageResponse]) -> [PageResponse] {`
- [950](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:950) `private func applyPageSkip(_ allPages: [URL]) -> [URL] {`
- [955](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:955) `private func persistReadingState(endSession: Bool, syncRemote: Bool) {`
- [991](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:991) `private static func prefetchNextChapter(comicId: UUID, chapterId: UUID) async {`
- [1005](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1005) `private func loadPages() async {`
- [1100](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1100) `struct ComicPageView: View {`
- [1132](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1132) `.onTapGesture { retryID = UUID() }`
- [1155](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1155) `private struct LocalPageView: View {`
- [1184](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1184) `private struct AutoScrollModifier: ViewModifier {`
- [1188](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1188) `func body(content: Content) -> some View {`
- [1195](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1195) `private struct AutoScrollFinder: UIViewRepresentable {`
- [1199](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1199) `func makeUIView(context: Context) -> UIView {`
- [1205](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1205) `func updateUIView(_ uiView: UIView, context: Context) {`
- [1215](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1215) `func makeCoordinator() -> Coordinator {`
- [1220](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1220) `class Coordinator {`
- [1229](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1229) `func startScrolling(in view: UIView) {`
- [1238](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1238) `func stopScrolling() {`
- [1243](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1243) `@objc private func tick() {`
- [1251](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1251) `private func findScrollView(in view: UIView) -> UIScrollView? {`
- [1271](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1271) `private struct ZoomablePageView<Content: View>: View {`
- [1287](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1287) `.simultaneousGesture(`
- [1316](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1316) `.onTapGesture(count: 2) {`
- [1352](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1352) `private struct PrevChapterTrigger: View {`
- [1397](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1397) `private struct NextChapterTrigger: View {`
- [1434](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1434) `private func chapterTriggerRing(progress: CGFloat, icon: String, label: String) -> some View {`
- [1461](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1461) `private struct ComicChapterListSheet: View {`
- [1472](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1472) `Button {`
- [1529](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1529) `Button("Done") { dismiss() }`
- [1538](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift:1538) `private func chapterNum(_ ch: LocalComicChapter) -> String {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:7) `struct ComicScrapesView: View {`
- [33](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:33) `Button {`
- [73](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:73) `Button(role: .destructive) {`
- [100](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:100) `.sheet(item: $selectedJob) { job in`
- [108](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:108) `private func syncActiveJobs() async {`
- [176](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:176) `private func deleteScrapeJob(_ job: LocalScrapeJob) {`
- [213](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:213) `struct ScrapeJobRow: View {`
- [281](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:281) `Button {`
- [299](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:299) `.onTapGesture(perform: onSelect)`
- [327](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:327) `private func retryJob() async {`
- [358](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:358) `private struct ComicScrapeJobDetailView: View {`
- [460](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:460) `Button("Done") { dismiss() }`
- [468](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:468) `private func loadLogs() async {`
- [475](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:475) `private func detailRow(label: String, value: String) -> some View {`
- [500](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:500) `private func dateText(_ date: Date) -> String {`
- [505](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Scrapes/ComicScrapesView.swift:505) `private struct ScrapeLogRow: View {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:8) `final class ChapterDownloadService {`
- [26](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:26) `func downloadChapter(`
- [119](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:119) `func downloadAllChapters(`
- [149](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:149) `func localPageURLs(for chapter: LocalComicChapter) -> [URL]? {`
- [176](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:176) `func deleteChapter(comicId: UUID, chapter: LocalComicChapter, modelContext: ModelContext) {`
- [190](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:190) `func deleteAllChapters(comic: LocalComic, chapters: [LocalComicChapter], modelContext: ModelContext) {`
- [208](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:208) `private nonisolated func validateImageData(_ data: Data, pageNumber: Int) throws {`
- [224](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:224) `private func checkDiskSpace(estimatedBytes: Int64) throws {`
- [236](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:236) `func downloadAllChaptersBackground(`
- [288](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift:288) `private func finalizeBackgroundChapter(`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Stats/StatsView.swift

- [10](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Stats/StatsView.swift:10) `struct StatsView: View {`

## ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift:7) `final class ComicLibraryViewModel {`
- [13](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift:13) `func fetchComics(modelContext: ModelContext, force: Bool = false) async {`
- [108](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift:108) `private static func encodeTagsJSON(_ tags: [TagResponse]?) -> String? {`
- [115](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift:115) `private static func encodeAuthorsJSON(_ authors: [AuthorResponse]?) -> String? {`
- [122](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift:122) `private func upsertChapters(`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:8) `struct FanficBrowserView: View {`
- [18](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:18) `Menu {`
- [20](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:20) `Button {`
- [57](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:57) `Button(action: viewModel.goBack) {`
- [63](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:63) `Button(action: viewModel.goForward) {`
- [69](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:69) `Button(action: viewModel.reload) {`
- [81](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:81) `TextField("Enter URL", text: $viewModel.addressBarText)`
- [94](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:94) `Button(action: {`
- [129](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:129) `Button {`
- [153](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:153) `.alert("AO3 Import", isPresented: Binding(`
- [157](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:157) `Button("OK", role: .cancel) { importError = nil }`
- [171](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:171) `private func sourceLabel(_ source: FanficSource) -> String {`
- [180](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:180) `final class FanficBrowserViewModel {`
- [202](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:202) `func navigateToAddress() {`
- [222](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:222) `func extractCookiesAndScrape() async -> LocalScrapeJob? {`
- [273](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:273) `func showToast(_ toast: ScrapeToast) {`
- [281](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:281) `func evaluateCanScrape(url: URL?) {`
- [295](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:295) `func goBack() { webView?.goBack() }`
- [296](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:296) `func goForward() { webView?.goForward() }`
- [297](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:297) `func reload() { webView?.reload() }`
- [299](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:299) `func resetToSourceHome() {`
- [313](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:313) `struct FanficWebViewRepresentable: UIViewRepresentable {`
- [316](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:316) `func makeUIView(context: Context) -> WKWebView {`
- [345](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:345) `func updateUIView(_ webView: WKWebView, context: Context) {`
- [352](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:352) `func makeCoordinator() -> Coordinator {`
- [356](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:356) `class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {`
- [367](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:367) `func webView(`
- [386](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:386) `func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {`
- [415](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:415) `func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {`
- [421](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:421) `func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {`
- [429](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:429) `func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {`
- [433](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:433) `func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {`
- [437](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:437) `func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {`
- [441](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Browser/FanficBrowserView.swift:441) `func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficSidebarView.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficSidebarView.swift:4) `struct FanficSidebarView: View {`
- [15](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficSidebarView.swift:15) `.onTapGesture {`
- [45](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficSidebarView.swift:45) `private func sidebarRow(_ section: FanficSection) -> some View {`
- [46](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficSidebarView.swift:46) `Button {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:5) `public struct FanficTabView: View {`
- [47](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:47) `Menu {`
- [48](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:48) `Button {`
- [55](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:55) `Button {`
- [76](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:76) `Button {`
- [89](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:89) `Button {`
- [100](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:100) `Button {`
- [124](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:124) `.sheet(isPresented: $showFilter) {`
- [136](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:136) `private func saveFilterPrefs() {`
- [145](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:145) `final class FanficNavigation {`
- [153](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:153) `func searchFor(_ term: String) {`
- [160](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:160) `private struct FanficNavigationKey: EnvironmentKey {`
- [171](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/FanficTabView.swift:171) `enum FanficSection: String, CaseIterable {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:7) `struct FanficDetailView: View {`
- [37](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:37) `private enum FanficDetailTab: String, CaseIterable {`
- [68](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:68) `Button {`
- [81](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:81) `Button {`
- [120](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:120) `Button {`
- [132](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:132) `.contextMenu {`
- [133](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:133) `Button {`
- [161](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:161) `Button {`
- [197](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:197) `.contextMenu {`
- [198](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:198) `Button(role: .destructive) {`
- [216](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:216) `.fullScreenCover(item: $selectedChapter) { chapter in`
- [223](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:223) `Button {`
- [239](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:239) `Menu {`
- [240](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:240) `Button(role: .destructive) {`
- [280](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:280) `private func syncChapters() async {`
- [454](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:454) `private func tagRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {`
- [466](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:466) `private func tappableTag(_ text: String, color: Color) -> some View {`
- [467](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:467) `Button {`
- [476](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:476) `private func ratingColor(_ rating: String) -> Color {`
- [485](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:485) `private func statPill(icon: String, value: String, label: String) -> some View {`
- [500](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:500) `private func formatStat(_ value: Int) -> String {`
- [506](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:506) `private func statusColor(_ status: String) -> Color {`
- [515](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:515) `private func handleDownloadTap() {`
- [549](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:549) `private func addBookmark(for chapter: LocalFanficChapter) {`
- [560](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:560) `private func rescrape() {`
- [574](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:574) `private func openAO3Import() {`
- [582](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:582) `private func deleteBookmark(_ bookmark: LocalBookmark) {`
- [590](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:590) `private struct FanficBookmarksSection: View {`
- [599](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:599) `Button {`
- [644](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:644) `Button {`
- [673](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:673) `private struct FanficChapterRow: View {`
- [747](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:747) `private func downloadStatusIcon(for chapter: LocalFanficChapter) -> some View {`
- [766](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:766) `private func statusIcon(for status: String) -> some View {`
- [792](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:792) `private struct FanficContinueReadingButton: View {`
- [797](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:797) `private enum ReadingState {`
- [818](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:818) `Button {`
- [836](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:836) `private func targetChapter(for state: ReadingState) -> LocalFanficChapter {`
- [842](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:842) `private func iconName(for state: ReadingState) -> String {`
- [850](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:850) `private func label(for state: ReadingState) -> String {`
- [865](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:865) `private func backgroundColor(for state: ReadingState) -> Color {`
- [872](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift:872) `private func labelColor(for state: ReadingState) -> Color {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterPrefs.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterPrefs.swift:4) `struct FanficFilterPrefs: Codable {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterState.swift

- [6](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterState.swift:6) `final class FanficFilterState {`
- [32](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterState.swift:32) `func reset() {`
- [46](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterState.swift:46) `func load(from prefs: FanficFilterPrefs) {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift:7) `struct FanficFilterView: View {`
- [116](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift:116) `Button("Reset") {`
- [122](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift:122) `Button("Done") {`
- [131](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterView.swift:131) `private func ratingLabel(_ rating: FanficRating) -> String {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:7) `struct FanficLibraryView: View {`
- [139](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:139) `Button("Browse AO3") {`
- [151](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:151) `NavigationLink {`
- [159](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:159) `.contextMenu {`
- [160](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:160) `Button(role: .destructive) {`
- [211](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:211) `private struct FanficContinueReadingStrip: View {`
- [236](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:236) `private struct FanficContinueCardLink: View {`
- [255](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:255) `NavigationLink {`
- [263](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:263) `private struct FanficContinueCard: View {`
- [313](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:313) `enum FanficSortOption: String, CaseIterable {`
- [324](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:324) `struct FanficRowView: View {`
- [334](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:334) `private func thumbnailURL(_ path: String) -> URL? {`
- [347](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:347) `private func formatRowStat(_ value: Int) -> String {`
- [413](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift:413) `Button {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:7) `struct FanficReaderView: View {`
- [137](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:137) `.simultaneousGesture(`
- [255](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:255) `.simultaneousGesture(`
- [306](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:306) `.sheet(isPresented: $showBookmarkSheet) {`
- [328](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:328) `.sheet(isPresented: $showChapterList) {`
- [362](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:362) `Button { dismiss() } label: {`
- [392](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:392) `Button { showChapterList = true } label: {`
- [397](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:397) `Button {`
- [412](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:412) `Button {`
- [454](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:454) `Button {`
- [476](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:476) `Button {`
- [515](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:515) `Button {`
- [537](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:537) `Slider(value: $fontSize, in: 12...28)`
- [545](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:545) `Stepper(value: $lineHeight, in: 1.2...2.2, step: 0.1) {`
- [555](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:555) `Stepper(value: $paragraphSpacing, in: 0...36, step: 2) {`
- [560](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:560) `Stepper(value: $horizontalMargin, in: 8...48, step: 2) {`
- [571](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:571) `Button {`
- [597](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:597) `private func sectionHeader(_ title: String) -> some View {`
- [604](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:604) `private func labeledReadout(_ label: String, value: String) -> some View {`
- [617](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:617) `private func bgPreviewColor(_ bg: ReaderBackground) -> Color {`
- [638](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:638) `private func isSceneBreak(_ text: String) -> Bool {`
- [644](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:644) `private func wordOffsetForParagraph(_ index: Int) -> Int {`
- [649](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:649) `private func persistReadingState(endSession: Bool, syncRemote: Bool) {`
- [681](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:681) `private func prefetchAdjacentChapters() async {`
- [696](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:696) `private func loadChapter() async {`
- [772](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:772) `Button {`
- [802](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:802) `Button {`
- [833](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:833) `private func chapterPlaceholder(chapter: LocalFanficChapter, direction: String, icon: String) -> some View {`
- [851](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:851) `private func chapterLabel(_ ch: LocalFanficChapter) -> String {`
- [860](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:860) `private func calculateScrollTarget() {`
- [880](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:880) `private func navigateTo(_ chapter: LocalFanficChapter) {`
- [905](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:905) `private struct FanficChapterListSheet: View {`
- [917](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:917) `Button {`
- [969](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:969) `Button("Done") { dismiss() }`
- [978](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:978) `private func chapterNum(_ ch: LocalFanficChapter) -> String {`
- [987](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:987) `private struct FanficBookmarkSheet: View {`
- [1013](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:1013) `TextField("Heading (optional)", text: $heading)`
- [1028](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:1028) `Button("Cancel") { dismiss() }`
- [1032](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:1032) `Button("Save") {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift

- [9](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:9) `struct FanficScrapesView: View {`
- [35](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:35) `Button {`
- [75](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:75) `Button(role: .destructive) {`
- [102](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:102) `.sheet(item: $selectedJob) { job in`
- [110](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:110) `private func syncActiveJobs() async {`
- [191](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:191) `private func deleteScrapeJob(_ job: LocalScrapeJob) {`
- [246](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:246) `struct FanficScrapeJobRow: View {`
- [314](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:314) `Button {`
- [332](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:332) `.onTapGesture(perform: onSelect)`
- [360](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:360) `private func retryJob() async {`
- [391](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:391) `private struct FanficScrapeJobDetailView: View {`
- [493](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:493) `Button("Done") { dismiss() }`
- [501](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:501) `private func loadLogs() async {`
- [508](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:508) `private func detailRow(label: String, value: String) -> some View {`
- [533](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:533) `private func dateText(_ date: Date) -> String {`
- [538](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Scrapes/FanficScrapesView.swift:538) `private struct FanficScrapeLogRow: View {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift

- [9](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:9) `final class AO3ImportService {`
- [13](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:13) `static func workURL(from url: URL?) -> URL? {`
- [22](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:22) `func importWork(from webView: WKWebView, modelContext: ModelContext) async throws -> LocalFanfic {`
- [143](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:143) `private static func date(_ string: String) -> Date? {`
- [152](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:152) `private struct AO3ImportResponse: Decodable {`
- [157](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:157) `private struct AO3WorkImport: Decodable, Sendable {`
- [178](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:178) `private struct AO3ChapterImport: Decodable, Sendable {`
- [187](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:187) `func write(_ chapters: [AO3ChapterImport], fanficID: UUID, importID: UUID) throws -> [String] {`
- [210](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:210) `func remove(_ paths: [String]) {`
- [223](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:223) `private struct AO3ImportError: LocalizedError {`
- [228](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/AO3ImportService.swift:228) `static func message(for code: String) -> Self {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift:7) `public final class FanficDownloadService {`
- [21](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift:21) `public func downloadChapter(`
- [98](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift:98) `public func downloadAllChapters(`
- [117](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift:117) `public func deleteAllChapters(`
- [147](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift:147) `private func chapterRelativePath(fanficId: UUID, chapterNumber: Double) -> String {`
- [158](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift:158) `private func checkDiskSpace() throws {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Stats/FanficStatsView.swift

- [9](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Stats/FanficStatsView.swift:9) `struct FanficStatsView: View {`

## ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift:7) `final class FanficLibraryViewModel {`
- [13](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift:13) `func fetchFanfics(`
- [162](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift:162) `private func upsertChapters(`

## ios/Astral/Packages/StatsUI/Sources/StatsUI/HeatmapDayDetailSheet.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/HeatmapDayDetailSheet.swift:8) `struct HeatmapDayDetailSheet: View {`
- [48](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/HeatmapDayDetailSheet.swift:48) `Button("Done") { dismiss() }`
- [72](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/HeatmapDayDetailSheet.swift:72) `private func rowView(_ row: StatsAggregates.DaySessionRow) -> some View {`
- [117](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/HeatmapDayDetailSheet.swift:117) `private func miniStat(value: String, label: String) -> some View {`

## ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift

- [17](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:17) `public struct SharedStatsView: View {`
- [59](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:59) `.sheet(item: $selectedDay) { day in`
- [147](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:147) `private func odometerCard(value: String, label: String, icon: String, sublabel: String?) -> some View {`
- [268](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:268) `private struct HeatmapCellData {`
- [273](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:273) `private func buildHeatmap() -> [HeatmapCellData] {`
- [294](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:294) `fileprivate static func heatmapColor(for count: Int) -> Color {`
- [304](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:304) `private func heatmapLevelColor(_ level: Int) -> Color {`
- [345](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:345) `private struct DayData {`
- [351](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:351) `private func buildWeekData() -> [DayData] {`
- [457](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:457) `private struct BacklogTier: Identifiable {`
- [507](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:507) `private struct AlmostDoneItem {`
- [544](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:544) `private struct VelocityData {`
- [675](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:675) `private func splitBadge(_ label: String, count: Int, icon: String, color: Color) -> some View {`
- [692](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:692) `private struct DistributionItem {`
- [854](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:854) `private func miniStat(value: String, label: String) -> some View {`
- [928](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:928) `private struct TimelineEvent: Identifiable {`
- [937](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:937) `private struct TimelineGroup: Identifiable {`
- [944](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:944) `private func buildTimeline() -> [TimelineGroup] {`
- [1004](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:1004) `private func sectionHeader(_ title: String, icon: String) -> some View {`
- [1016](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:1016) `private struct HeatmapCell: View {`
- [1022](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:1022) `Button {`
- [1036](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:1036) `private struct HighlightCard: View {`
- [1072](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/SharedStatsView.swift:1072) `private struct SelectedDay: Identifiable {`

## ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:8) `public struct StatsAggregates {`
- [115](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:115) `public struct WeeklyMinutes: Identifiable, Equatable {`
- [122](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:122) `public func weeklyReadingMinutes(weeks: Int = 12) -> [WeeklyMinutes] {`
- [148](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:148) `public struct TagCount: Identifiable, Equatable {`
- [156](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:156) `public func topTags(limit: Int = 12) -> [TagCount] {`
- [169](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:169) `private static func parseJSONStrings(_ raw: String?) -> [String] {`
- [174](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:174) `private static func splitCommaList(_ raw: String?) -> [String] {`
- [180](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:180) `private static func addTags(_ tags: [String], into counts: inout [String: Int]) {`
- [190](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:190) `public struct DaySessionRow: Identifiable, Equatable {`
- [200](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:200) `public func sessionsOn(day: Date) -> [DaySessionRow] {`
- [229](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:229) `public struct BookmarkedStory: Identifiable, Equatable {`
- [241](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:241) `public func mostBookmarkedStories(limit: Int = 5) -> [BookmarkedStory] {`
- [263](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:263) `public struct WeeklyBookmarks: Identifiable, Equatable {`
- [270](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:270) `public func weeklyBookmarkActivity(weeks: Int = 12) -> [WeeklyBookmarks] {`
- [302](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:302) `public enum StatsFormat {`
- [303](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:303) `public static func duration(_ seconds: TimeInterval) -> String {`
- [313](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:313) `public static func shortDuration(_ seconds: TimeInterval) -> String {`
- [321](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/StatsUI/Sources/StatsUI/StatsData.swift:321) `public static func compactNumber(_ n: Int) -> String {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:7) `public enum AstralAnimation {`
- [41](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:41) `public static func stagger(index: Int, base: Double = 0.045) -> Animation {`
- [50](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:50) `public struct PressButtonStyle: ButtonStyle {`
- [57](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:57) `public func makeBody(configuration: Configuration) -> some View {`
- [69](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:69) `struct StaggeredAppearModifier: ViewModifier {`
- [73](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:73) `func body(content: Content) -> some View {`
- [89](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:89) `func pressEffect(scale: CGFloat = 0.96) -> some View {`
- [94](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/AstralAnimations.swift:94) `func staggeredAppear(index: Int) -> some View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Colors.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Colors.swift:5) `public enum AstralColors {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralLogo.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralLogo.swift:5) `public enum AstralLogoSize {`
- [26](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralLogo.swift:26) `public struct AstralLogo: View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralSearchBar.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralSearchBar.swift:5) `public struct AstralSearchBar: View {`
- [23](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralSearchBar.swift:23) `TextField(placeholder, text: $text)`
- [31](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralSearchBar.swift:31) `Button {`
- [41](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/AstralSearchBar.swift:41) `Button {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/BackendStatusBanner.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/BackendStatusBanner.swift:4) `public struct BackendStatusBanner: View {`
- [26](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/BackendStatusBanner.swift:26) `Button {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift

- [6](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift:6) `public struct CachedAsyncImage: View {`
- [51](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift:51) `private func loadImage() async {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift

- [6](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:6) `public struct DebugConsoleView: View {`
- [46](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:46) `Button("Clear") {`
- [53](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:53) `Button("Done") { dismiss() }`
- [69](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:69) `private func filterChip(_ level: LogLevel?, label: String) -> some View {`
- [71](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:71) `Button {`
- [86](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:86) `private func logRow(_ entry: LogEntry) -> some View {`
- [105](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:105) `private func logColor(_ level: LogLevel) -> Color {`
- [119](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:119) `public struct DebugShakeDetector<Content: View>: View {`
- [132](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:132) `.sheet(isPresented: $showConsole) {`
- [141](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:141) `func onShake(perform action: @escaping () -> Void) -> some View {`
- [146](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:146) `private struct ShakeDetectorView: UIViewControllerRepresentable {`
- [149](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:149) `func makeUIViewController(context: Context) -> ShakeViewController {`
- [153](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:153) `func updateUIViewController(_ uiViewController: ShakeViewController, context: Context) {}`
- [156](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:156) `private class ShakeViewController: UIViewController {`
- [168](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:168) `override func viewDidAppear(_ animated: Bool) {`
- [173](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/DebugConsoleView.swift:173) `override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/EmptyStateView.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/EmptyStateView.swift:3) `public struct EmptyStateView: View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/GoldButton.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/GoldButton.swift:3) `public struct GoldButton: View {`
- [15](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/GoldButton.swift:15) `Button(action: action) {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterChips.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterChips.swift:4) `public struct FilterStatusChip: View {`
- [16](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterChips.swift:16) `Button(action: action) {`
- [34](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterChips.swift:34) `public struct FilterToggleChip: View {`
- [46](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterChips.swift:46) `Button(action: action) {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterSectionCard.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterSectionCard.swift:4) `public struct FilterSectionCard<Content: View>: View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterSortDirectionToggle.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterSortDirectionToggle.swift:4) `public struct FilterSortDirectionToggle: View {`
- [12](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterSortDirectionToggle.swift:12) `Button {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterTextField.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterTextField.swift:4) `public struct FilterTextField: View {`
- [22](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterTextField.swift:22) `TextField(placeholder, text: $text)`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FlowLayout.swift

- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FlowLayout.swift:4) `public struct FlowLayout: Layout {`
- [11](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FlowLayout.swift:11) `public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {`
- [32](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FlowLayout.swift:32) `public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/PlaceholderThumbnail.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/PlaceholderThumbnail.swift:5) `public struct PlaceholderThumbnail: View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/ProgressBarView.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/ProgressBarView.swift:3) `public struct ProgressBarView: View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift:3) `public struct StatusBadge: View {`
- [24](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift:24) `static func downloaded() -> StatusBadge {`
- [28](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift:28) `static func partial() -> StatusBadge {`
- [32](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift:32) `static func failed() -> StatusBadge {`
- [36](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift:36) `static func scraping() -> StatusBadge {`
- [40](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift:40) `static func savedToDevice() -> StatusBadge {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StoryThumbnail.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StoryThumbnail.swift:5) `public struct StoryThumbnail: View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/ToastView.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/ToastView.swift:3) `public struct ScrapeToast: Equatable {`
- [12](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/ToastView.swift:12) `public struct ToastView: View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ContentBlocker.swift

- [6](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ContentBlocker.swift:6) `public final class ContentBlocker {`
- [15](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ContentBlocker.swift:15) `public func precompile() {`
- [38](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ContentBlocker.swift:38) `public func apply(to webView: WKWebView) {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift:3) `public struct DeletePermanentlyAlertModifier: ViewModifier {`
- [14](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift:14) `public func body(content: Content) -> some View {`
- [15](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift:15) `content.alert("Delete Permanently?", isPresented: $isPresented) {`
- [16](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift:16) `Button("Cancel", role: .cancel) { }`
- [17](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift:17) `Button("Delete", role: .destructive) { onConfirm() }`
- [25](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/DeletePermanentlyAlertModifier.swift:25) `func deletePermanentlyAlert(`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift

- [5](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift:5) `public enum HapticEvent {`
- [14](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift:14) `public enum Haptics {`
- [18](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Haptics.swift:18) `public static func play(_ event: HapticEvent) {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/CardModifier.swift

- [3](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/CardModifier.swift:3) `public struct AstralCardModifier: ViewModifier {`
- [4](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/CardModifier.swift:4) `public func body(content: Content) -> some View {`
- [16](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/CardModifier.swift:16) `func astralCard() -> some View {`
- [21](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/CardModifier.swift:21) `public struct OfflineBannerModifier: ViewModifier {`
- [24](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/CardModifier.swift:24) `public func body(content: Content) -> some View {`
- [43](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/CardModifier.swift:43) `func offlineBanner(isOffline: Bool) -> some View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift

- [8](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift:8) `public struct PressRevealModifier: ViewModifier {`
- [12](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift:12) `public func body(content: Content) -> some View {`
- [13](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift:13) `content.simultaneousGesture(`
- [29](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Modifiers/PressReveal.swift:29) `func pressReveal(perform action: @escaping () -> Void) -> some View {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ReaderMotion.swift

- [6](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/ReaderMotion.swift:6) `public enum ReaderMotion {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift

- [7](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift:7) `public final class ThrottledSetter<T: Equatable> {`
- [21](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift:21) `public func set(_ value: T, apply: (T) -> Void) -> Bool {`
- [33](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Throttle/ThrottledSetter.swift:33) `public func reset() {`

## ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Typography.swift

- [6](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Typography.swift:6) `public enum AstralTypography {`
- [16](/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp/ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Typography.swift:16) `public static func readerFont(size: CGFloat, lineHeight: CGFloat = 1.6) -> Font {`
