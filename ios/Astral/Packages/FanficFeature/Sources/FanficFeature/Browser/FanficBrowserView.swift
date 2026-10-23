import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import WebKit
import Core
import DesignSystem
import Networking

struct FanficBrowserView: View {
    @State private var showFileImport = false
    @State private var fileImportMessage: String?

    @State private var viewModel = FanficBrowserViewModel()
    @State private var importError: String?
    @State private var importTask: Task<Void, Never>?
    @State private var importedWork: LocalFanfic?
    @State private var readingWork: LocalFanfic?
    @Query private var fanfics: [LocalFanfic]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fanficNavigation) private var fanficNavigation

    /// Chrome steps aside while a page is read, but stays during an import.
    private var chromeCollapsed: Bool { viewModel.chrome.isCollapsed && !viewModel.isScraping }

    var body: some View {
        VStack(spacing: 0) {
            // One row of chrome: source, address and file import.
            if !chromeCollapsed {
                HStack(spacing: 8) {
                    BrowserSourceMenu(sources: FanficSource.allCases, selection: $viewModel.selectedSource,
                                      isDisabled: viewModel.isScraping, label: \.displayName,
                                      shortLabel: { $0 == .ffnet ? "FFN" : $0.displayName })
                    BrowserAddressBar(text: $viewModel.addressBarText, url: viewModel.currentURL,
                                      progress: viewModel.loadProgress, isLoading: viewModel.isLoading,
                                      prompt: "Search \(viewModel.selectedSource.displayName) or enter address",
                                      onSubmit: viewModel.navigateToAddress, onReload: viewModel.reload, onStop: viewModel.stop)
                        .disabled(viewModel.isScraping)
                    fileImportButton
                }
                .padding(.leading, 12).padding(.trailing, 4).padding(.top, 6).padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            // Imports fetch chapters in a hidden page, so browsing stays available.
            FanficWebViewRepresentable(viewModel: viewModel)
        }
        .background(AstralColors.background)
        .animation(.easeInOut(duration: 0.2), value: chromeCollapsed)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chromeCollapsed {
                VStack(spacing: 8) {
                    if let importedWork, !viewModel.isScraping {
                        BrowserImportBanner(title: importedWork.title, primaryTitle: "Read now",
                                            onPrimary: { readingWork = importedWork },
                                            onDismiss: { self.importedWork = nil })
                    }
                    BrowserBottomBar(canGoBack: viewModel.canGoBack, canGoForward: viewModel.canGoForward, state: importState,
                                     onBack: viewModel.goBack, onForward: viewModel.goForward,
                                     onImport: startImport, onOpen: { readingWork = existingWork }, onCancel: cancelImport) {
                        browserMenu
                    }
                }
                .animation(AstralAnimation.smooth, value: importedWork?.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $showFileImport, allowedContentTypes: [.plainText]) { result in
            do {
                let story = try LocalFileImportService.importText(result.get(), context: modelContext)
                fileImportMessage = "Saved: " + story.title + ". Open it from Library or Activity."
            } catch { fileImportMessage = error.localizedDescription }
        }
        .alert("File import", isPresented: Binding(get: { fileImportMessage != nil }, set: { if !$0 { fileImportMessage = nil } })) {
            Button("OK") { fileImportMessage = nil }
        } message: { Text(fileImportMessage ?? "") }
        .fullScreenCover(item: $readingWork) { work in
            ImportedFanficReader(fanfic: work)
        }
        .onAppear {
            if let url = fanficNavigation?.ao3WorkURL {
                viewModel.selectedSource = AO3ImportService.ffnetURL(from: url) != nil ? .ffnet : .ao3
                viewModel.savedURLs[viewModel.selectedSource] = url
                viewModel.webView?.load(URLRequest(url: url))
            }
        }
        .alert("Story import", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .overlay(alignment: .top) {
            if let toast = viewModel.scrapeToast {
                ToastView(toast.message, isSuccess: toast.isSuccess)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 104)
            }
        }
        .animation(AstralAnimation.smooth, value: viewModel.scrapeToast?.message)
    }

    /// The saved story for the work that is open, matched by its canonical source URL.
    private var existingWork: LocalFanfic? {
        guard let url = viewModel.currentURL,
              let canonical = AO3ImportService.workURL(from: url) ?? AO3ImportService.ffnetURL(from: url) else { return nil }
        return fanfics.first { story in
            story.sourceUrl.flatMap(URL.init(string:)).flatMap { AO3ImportService.workURL(from: $0) ?? AO3ImportService.ffnetURL(from: $0) } == canonical
        }
    }

    private var importState: BrowserImportState {
        if viewModel.isScraping { return .importing("Saving chapters…") }
        // A long FFNet import that stopped part-way keeps its chapters; importing again resumes it.
        if let work = existingWork, work.sourceKey == "ffnet", let saved = work.chapters?.count, saved < work.totalChapters {
            return .ready("Continue import · \(saved) of \(work.totalChapters)")
        }
        if existingWork != nil { return .inLibrary("In library · Read") }
        if viewModel.canScrape && !viewModel.isLoading { return .ready("Add to library") }
        if viewModel.canScrape { return .unavailable("Loading the story…") }
        return .unavailable(viewModel.selectedSource == .ao3 ? "Open a work to add it" : "Open a story to add it")
    }

    @ViewBuilder private var browserMenu: some View {
        if existingWork != nil {
            Button("Update from \(viewModel.selectedSource.displayName)", systemImage: "arrow.triangle.2.circlepath") { startImport() }
                .disabled(viewModel.isScraping || viewModel.isLoading)
        }
        Button("\(viewModel.selectedSource.displayName) home", systemImage: "house") { viewModel.resetToSourceHome() }
        if let url = viewModel.currentURL {
            Button("Open in Safari", systemImage: "safari") { UIApplication.shared.open(url) }
            ShareLink(item: url) { Label("Share page", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button("Import text file", systemImage: "doc.badge.plus") { showFileImport = true }
    }

    private func startImport() {
        guard let webView = viewModel.webView, !viewModel.isScraping else { return }
        importTask = Task { @MainActor in
            viewModel.isScraping = true
            defer { viewModel.isScraping = false }
            do {
                importedWork = try await AO3ImportService.shared.importWork(from: webView, modelContext: modelContext, onCancel: { cancelImport() })
                fanficNavigation?.ao3WorkURL = nil
                Haptics.play(.bookmark)
            } catch is CancellationError {
                // Leaving an import doesn't create a partial library entry.
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private var fileImportButton: some View {
        Button("Import text file", systemImage: "doc.badge.plus") { showFileImport = true }
            .labelStyle(.iconOnly)
            .foregroundStyle(AstralColors.body)
            .frame(width: 40, height: 40)
            .accessibilityHint("Choose a UTF-8 text file to save as a single chapter.")
            .accessibilityIdentifier("fanfic.browser.fileImport")
            .disabled(viewModel.isScraping)
    }

    private func cancelImport() {
        importTask?.cancel()
        if let webView = viewModel.webView {
            Task { @MainActor in
                _ = try? await webView.callAsyncJavaScript("globalThis.__astralAO3ImportAbort?.abort()", arguments: [:], in: nil, contentWorld: .defaultClient)
            }
        }
    }

}

@MainActor @Observable
final class FanficBrowserViewModel {
    var selectedSource: FanficSource = .ao3
    var canScrape = false
    var isScraping = false
    var isLoading = false
    var loadProgress: Double = 0
    var cookieCount: Int = 0
    var scrapeToast: ScrapeToast? = nil
    var currentURL: URL?
    var addressBarText: String = ""
    var webView: WKWebView?
    var savedURLs: [FanficSource: URL] = [:]
    var canGoBack = false
    var canGoForward = false
    let chrome = BrowserChromeVisibility()

    var allowedDomains: [String] {
        switch selectedSource {
        case .ao3: return ["archiveofourown.org"]
        case .ffnet: return ["fanfiction.net"]
        }
    }

    func navigateToAddress() {
        guard let url = BrowserAddress.url(for: addressBarText, search: searchURL) else { return }
        webView?.load(URLRequest(url: url))
    }

    /// Plain words search the selected source instead of failing as an address.
    func searchURL(_ text: String) -> URL? {
        let query = BrowserAddress.query(text)
        switch selectedSource {
        case .ao3: return URL(string: "https://archiveofourown.org/works/search?work_search%5Bquery%5D=\(query)")
        case .ffnet: return URL(string: "https://www.fanfiction.net/search/?keywords=\(query)&type=story")
        }
    }

    var sourceURL: URL {
        if let saved = savedURLs[selectedSource] {
            return saved
        }
        switch selectedSource {
        case .ao3: return URL(string: "https://archiveofourown.org")!
        case .ffnet: return URL(string: "https://www.fanfiction.net")!
        }
    }

    func extractCookiesAndScrape() async -> LocalScrapeJob? {
        guard let webView, let url = currentURL, !isScraping else { return nil }
        isScraping = true
        defer { isScraping = false }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await store.allCookies()

        let sourceCookies = CookieStore.shared.filterCookies(
            allCookies,
            forSource: selectedSource.rawValue
        )

        let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String

        let request = ScrapeRequest(
            url: url.absoluteString,
            sourceKey: selectedSource.rawValue,
            cookies: sourceCookies,
            userAgent: ua ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)",
            contentType: "fanfic"
        )

        do {
            let response: ScrapeJobResponse = try await APIClient.shared.request(.initiateScrape(request))
            let alreadyDone = response.status == "complete" || response.status == "partial"
            showToast(ScrapeToast(message: alreadyDone ? "Already in library" : "Scrape queued", isSuccess: true))
            return LocalScrapeJob(
                id: response.id,
                contentType: response.contentType,
                storyId: response.storyId,
                status: response.status,
                chaptersScraped: response.chaptersScraped,
                chaptersFailed: response.chaptersFailed,
                totalChapters: response.totalChapters,
                createdAt: response.createdAt,
                completedAt: response.completedAt,
                sourceUrl: response.sourceUrl,
                sourceKey: response.sourceKey,
                jobType: response.jobType,
                errorMessage: response.errorMessage,
                currentStep: response.currentStep,
                lastErrorType: response.lastErrorType,
                startedAt: response.startedAt
            )
        } catch {
            showToast(ScrapeToast(message: "Scrape failed: \(error.localizedDescription)", isSuccess: false))
            return nil
        }
    }

    func showToast(_ toast: ScrapeToast) {
        scrapeToast = toast
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            scrapeToast = nil
        }
    }

    func evaluateCanScrape(url: URL?) {
        guard let url = url else {
            canScrape = false
            return
        }
        switch selectedSource {
        case .ao3:
            canScrape = AO3ImportService.workURL(from: url) != nil
        case .ffnet:
            canScrape = AO3ImportService.ffnetURL(from: url) != nil
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stop() { webView?.stopLoading() }

    func resetToSourceHome() {
        savedURLs.removeValue(forKey: selectedSource)
        let homeURL: URL
        switch selectedSource {
        case .ao3: homeURL = URL(string: "https://archiveofourown.org")!
        case .ffnet: homeURL = URL(string: "https://www.fanfiction.net")!
        }
        webView?.load(URLRequest(url: homeURL))
        addressBarText = homeURL.absoluteString
    }
}

// MARK: - WebView

struct FanficWebViewRepresentable: UIViewRepresentable {
    let viewModel: FanficBrowserViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        viewModel.webView = webView
        viewModel.chrome.track(webView.scrollView)
        ContentBlocker.shared.apply(to: webView)
        webView.load(URLRequest(url: viewModel.sourceURL))
        context.coordinator.loadedSource = viewModel.selectedSource

        context.coordinator.progressObservation = webView.observe(\.estimatedProgress) { webView, _ in
            Task { @MainActor in
                viewModel.loadProgress = webView.estimatedProgress
            }
        }
        context.coordinator.loadingObservation = webView.observe(\.isLoading) { webView, _ in
            Task { @MainActor in
                viewModel.isLoading = webView.isLoading
            }
        }
        // Client-side navigation changes the URL and history without didFinish.
        context.coordinator.urlObservation = webView.observe(\.url) { webView, _ in
            Task { @MainActor in
                if viewModel.currentURL != webView.url { viewModel.chrome.reveal() }
                viewModel.currentURL = webView.url
                viewModel.addressBarText = webView.url?.absoluteString ?? ""
                viewModel.evaluateCanScrape(url: webView.url)
            }
        }
        context.coordinator.historyObservations = [
            webView.observe(\.canGoBack) { webView, _ in Task { @MainActor in viewModel.canGoBack = webView.canGoBack } },
            webView.observe(\.canGoForward) { webView, _ in Task { @MainActor in viewModel.canGoForward = webView.canGoForward } },
        ]
        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(AstralColors.gold)
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedSource != viewModel.selectedSource {
            context.coordinator.loadedSource = viewModel.selectedSource
            webView.load(URLRequest(url: viewModel.sourceURL))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let viewModel: FanficBrowserViewModel
        var loadedSource: FanficSource
        var progressObservation: NSKeyValueObservation?
        var loadingObservation: NSKeyValueObservation?
        var urlObservation: NSKeyValueObservation?
        var historyObservations: [NSKeyValueObservation] = []

        init(viewModel: FanficBrowserViewModel) {
            self.viewModel = viewModel
            self.loadedSource = viewModel.selectedSource
        }

        @MainActor @objc func pullToRefresh(_ control: UIRefreshControl) {
            viewModel.reload()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                control.endRefreshing()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other && navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }
            guard let host = navigationAction.request.url?.host?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            let allowed = viewModel.allowedDomains.contains { domain in
                host == domain || host.hasSuffix("." + domain)
            }
            // Author links (Tumblr, Discord…) leave the importer and open in Safari.
            if !allowed && navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
               ["https", "http"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.currentURL = webView.url
            viewModel.addressBarText = webView.url?.absoluteString ?? ""
            if let url = webView.url {
                viewModel.savedURLs[viewModel.selectedSource] = url
            }
            viewModel.evaluateCanScrape(url: webView.url)
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward

            Task {
                let store = webView.configuration.websiteDataStore.httpCookieStore
                let allCookies = await store.allCookies()
                let sourceCookies = CookieStore.shared.filterCookies(
                    allCookies,
                    forSource: viewModel.selectedSource.rawValue
                )
                viewModel.cookieCount = sourceCookies.count
                if !sourceCookies.isEmpty {
                    let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String
                    CookieStore.shared.storeCookies(
                        sourceCookies,
                        forSource: viewModel.selectedSource.rawValue,
                        userAgent: ua ?? ""
                    )
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            viewModel.showToast(ScrapeToast(message: "Page failed: \(nsError.localizedDescription)", isSuccess: false))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            viewModel.showToast(ScrapeToast(message: "Cannot load page", isSuccess: false))
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
            completionHandler(false)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            completionHandler(nil)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            return nil
        }
    }
}

private struct ImportedFanficReader: View {
    let fanfic: LocalFanfic
    @Query private var chapters: [LocalFanficChapter]
    init(fanfic: LocalFanfic) {
        self.fanfic = fanfic
        let id = fanfic.id
        _chapters = Query(filter: #Predicate<LocalFanficChapter> { $0.fanficId == id }, sort: \LocalFanficChapter.chapterNumber)
    }
    var body: some View {
        if let chapter = chapters.first(where: { $0.id == ReadingPositionStore.position(story: fanfic.id)?.chapterID }) ?? chapters.first {
            FanficReaderView(fanfic: fanfic, chapters: chapters, chapter: chapter)
        }
    }
}
