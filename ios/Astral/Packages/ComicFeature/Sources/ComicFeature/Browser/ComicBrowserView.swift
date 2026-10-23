import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import WebKit
import Core
import DesignSystem
import Networking

struct ComicBrowserView: View {
    @State private var importTask: Task<Void, Never>?
    @State private var showFileImport = false
    @State private var fileImportMessage: String?
    @State private var importedComic: LocalComic?
    @State private var openComic: LocalComic?

    @State private var viewModel = ComicBrowserViewModel()
    @Query(filter: #Predicate<LocalComic> { $0.status != "deleted" }) private var comics: [LocalComic]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.comicNavigation) private var comicNavigation

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BrowserSourceChips(sources: ComicSource.browserOrder, selection: $viewModel.selectedSource,
                                   isDisabled: viewModel.isScraping, label: \.displayName)
                fileImportButton.padding(.trailing, 12)
            }
            .padding(.top, 6)
            BrowserAddressBar(text: $viewModel.addressBarText, url: viewModel.currentURL,
                              progress: viewModel.loadProgress, isLoading: viewModel.isLoading,
                              prompt: "Search \(viewModel.selectedSource.displayName) or enter address",
                              onSubmit: viewModel.navigateToAddress, onReload: viewModel.reload, onStop: viewModel.stop)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .disabled(viewModel.isScraping)
            ComicWebViewRepresentable(viewModel: viewModel)
                .allowsHitTesting(!viewModel.isScraping)
        }
        .background(AstralColors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let importedComic, !viewModel.isScraping {
                    BrowserImportBanner(title: importedComic.title, primaryTitle: "Open",
                                        onPrimary: { openComic = importedComic },
                                        onDismiss: { self.importedComic = nil })
                }
                BrowserBottomBar(canGoBack: viewModel.canGoBack, canGoForward: viewModel.canGoForward, state: importState,
                                 onBack: viewModel.goBack, onForward: viewModel.goForward,
                                 onImport: startImport, onOpen: { openComic = existingComic }, onCancel: cancelImport) {
                    browserMenu
                }
            }
            .animation(AstralAnimation.smooth, value: importedComic?.id)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openComic) { comic in ComicDetailView(comic: comic) }
        .onAppear { openRequestedSource() }
        .onChange(of: comicNavigation?.sourceURL) { _, _ in openRequestedSource() }
        .fileImporter(isPresented: $showFileImport, allowedContentTypes: [.folder]) { result in
            importTask = Task { @MainActor in
                viewModel.isScraping = true
                defer { viewModel.isScraping = false }
                do {
                    importedComic = try await LocalFileImportService.importComicFolder(result.get(), context: modelContext, onCancel: { importTask?.cancel() })
                } catch is CancellationError {
                } catch { fileImportMessage = error.localizedDescription }
            }
        }
        .alert("Couldn't add comic", isPresented: Binding(get: { fileImportMessage != nil }, set: { if !$0 { fileImportMessage = nil } })) {
            Button("OK") { fileImportMessage = nil }
        } message: { Text(fileImportMessage ?? "") }

        .sheet(item: Binding(
            get: { viewModel.matchProposal.map { MatchProposalIdentifiable(payload: $0) } },
            set: { newValue in viewModel.matchProposal = newValue?.payload }
        )) { wrapper in
            MangaDexMatchDialog(
                match: wrapper.payload,
                originalSource: viewModel.pendingOriginalRequest?.sourceKey ?? "",
                onAccept: { viewModel.acceptMatch(modelContext: modelContext) },
                onDecline: { viewModel.declineMatch(modelContext: modelContext) }
            )
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

    /// The saved comic for the series that is open. MangaDex comics use the
    /// title UUID as their ID; browser sources are matched by series path.
    private var existingComic: LocalComic? {
        let source = viewModel.selectedSource
        if source == .mangadex {
            guard let id = MangaDexDeviceService.titleID(viewModel.currentURL) else { return nil }
            return comics.first { $0.id == id }
        }
        guard let canonical = DeviceComicService.canonical(viewModel.currentURL, source: source.rawValue) else { return nil }
        return comics.first {
            $0.sourceKey == source.rawValue &&
            UserDefaults.standard.string(forKey: "reading.source." + $0.id.uuidString).flatMap(URL.init(string:))?.path == canonical.path
        }
    }

    private var canImport: Bool {
        viewModel.selectedSource == .mangadex
            ? MangaDexDeviceService.titleID(viewModel.currentURL) != nil
            : viewModel.canScrape && !viewModel.isLoading
    }

    private var importState: BrowserImportState {
        if viewModel.isScraping { return .importing(viewModel.selectedSource == .mangadex ? "Fetching chapters…" : "Reading series…") }
        if existingComic != nil { return .inLibrary("In library · Open") }
        if canImport { return .ready("Add to library") }
        // MangaDex imports through its API, so page loading never gates them.
        if viewModel.canScrape && viewModel.selectedSource != .mangadex { return .unavailable("Loading the series…") }
        return .unavailable(viewModel.selectedSource == .mangadex ? "Open a title to add it" : "Open a series to add it")
    }

    @ViewBuilder private var browserMenu: some View {
        if existingComic != nil {
            Button("Check for new chapters", systemImage: "arrow.triangle.2.circlepath") { startImport() }
                .disabled(viewModel.isScraping || !canImport)
        }
        Button("\(viewModel.selectedSource.displayName) home", systemImage: "house") { viewModel.resetToSourceHome() }
        if let url = viewModel.currentURL {
            Button("Open in Safari", systemImage: "safari") { UIApplication.shared.open(url) }
            ShareLink(item: url) { Label("Share page", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button("Import image folder", systemImage: "folder.badge.plus") { showFileImport = true }
    }

    private func startImport() {
        guard !viewModel.isScraping else { return }
        importTask = Task { @MainActor in
            viewModel.isScraping = true
            defer { viewModel.isScraping = false }
            do {
                if viewModel.selectedSource == .mangadex {
                    guard let id = MangaDexDeviceService.titleID(viewModel.currentURL) else { return }
                    importedComic = try await MangaDexDeviceService.importTitle(id, context: modelContext, onCancel: { importTask?.cancel() })
                } else if let browser = viewModel.webView {
                    importedComic = try await DeviceComicService.importTitle(from: browser, source: viewModel.selectedSource.rawValue, context: modelContext, onCancel: { cancelImport() })
                }
                Haptics.play(.bookmark)
            } catch is CancellationError {
            } catch { fileImportMessage = error.localizedDescription }
        }
    }

    private var fileImportButton: some View {
        Button("Import image folder", systemImage: "folder.badge.plus") { showFileImport = true }
            .labelStyle(.iconOnly)
            .foregroundStyle(AstralColors.body)
            .frame(width: 40, height: 40)
            .accessibilityHint("Choose a folder of page images. Subfolders become chapters, sorted by name.")
            .accessibilityIdentifier("comic.browser.fileImport")
            .disabled(viewModel.isScraping)
    }

    private func cancelImport() {
        importTask?.cancel()
        guard let browser = viewModel.webView else { return }
        Task { @MainActor in _ = try? await browser.callAsyncJavaScript("globalThis.__astralComicImportAbort?.abort()", arguments: [:], in: nil, contentWorld: .defaultClient) }
    }
    private func openRequestedSource() {
        guard let url = comicNavigation?.sourceURL else { return }
        if let source = comicNavigation?.sourceKey { viewModel.selectedSource = source }
        viewModel.savedURLs[viewModel.selectedSource] = url
        viewModel.webView?.load(URLRequest(url: url))
        comicNavigation?.sourceURL = nil
    }

}

extension ComicSource {
    static let browserOrder: [ComicSource] = [.mangadex, .toongod, .hentai20, .nhentai]
}

@MainActor @Observable
final class ComicBrowserViewModel {
    var selectedSource: ComicSource = .mangadex
    var canScrape = false
    var isScraping = false
    var isLoading = false
    var loadProgress: Double = 0
    var cookieCount: Int = 0
    var scrapeToast: ScrapeToast? = nil
    var currentURL: URL?
    var addressBarText: String = ""
    var webView: WKWebView?
    var savedURLs: [ComicSource: URL] = [:]
    var canGoBack = false
    var canGoForward = false

    // AST-30 — MangaDex match flow
    var matchProposal: MangaDexMatchPayload? = nil
    var pendingOriginalRequest: ScrapeRequest? = nil
    var pendingPageTitle: String? = nil

    /// Allowed domains per source — blocks ad redirects to unrelated sites.
    var allowedDomains: [String] {
        switch selectedSource {
        case .nhentai: return ["nhentai.net", "nhentai.to"]
        case .toongod: return ["toongod.org", "toongod.com"]
        case .hentai20: return ["hentai20.io"]
        case .mangadex: return ["mangadex.org"]
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
        case .mangadex: return URL(string: "https://mangadex.org/search?q=\(query)")
        case .toongod: return URL(string: "https://www.toongod.org/?s=\(query)&post_type=wp-manga")
        case .hentai20: return URL(string: "https://hentai20.io/?s=\(query)&post_type=wp-manga")
        case .nhentai: return URL(string: "https://nhentai.net/search/?q=\(query)")
        }
    }

    var sourceURL: URL {
        if let saved = savedURLs[selectedSource] {
            return saved
        }
        switch selectedSource {
        case .nhentai: return URL(string: "https://nhentai.net")!
        case .toongod: return URL(string: "https://www.toongod.org")!
        case .hentai20: return URL(string: "https://hentai20.io")!
        case .mangadex: return URL(string: "https://mangadex.org")!
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
        let pageTitle = try? await webView.evaluateJavaScript("document.title") as? String

        let request = ScrapeRequest(
            url: url.absoluteString,
            sourceKey: selectedSource.rawValue,
            cookies: sourceCookies,
            userAgent: ua ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)",
            contentType: "comic",
            pageTitle: pageTitle ?? nil
        )
        pendingPageTitle = pageTitle ?? nil

        return await submitAndHandle(request)
    }

    /// Submits a ScrapeRequest. On a match-proposed outcome, stores the proposal
    /// (driving the dialog) and returns nil — the dialog's accept/decline
    /// callbacks finish the flow via acceptMatch/declineMatch.
    private func submitAndHandle(_ request: ScrapeRequest) async -> LocalScrapeJob? {
        do {
            let outcome = try await APIClient.shared.submitScrape(request)
            switch outcome {
            case .jobCreated(let response):
                let alreadyDone = response.status == "complete" || response.status == "partial"
                showToast(ScrapeToast(
                    message: alreadyDone ? "Already in library" : "Scrape queued",
                    isSuccess: true
                ))
                pendingOriginalRequest = nil
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
            case .matchProposed(let match):
                pendingOriginalRequest = request
                matchProposal = match
                return nil
            }
        } catch {
            showToast(ScrapeToast(message: "Scrape failed: \(error.localizedDescription)", isSuccess: false))
            return nil
        }
    }

    /// Called when the user taps "Use MangaDex" in the match dialog.
    func acceptMatch(modelContext: ModelContext) {
        guard let match = matchProposal,
              let original = pendingOriginalRequest else { return }
        matchProposal = nil
        Task {
            // Re-submit pointing at MangaDex; cookies/UA empty since we don't
            // have MangaDex cookies on hand and the API is public.
            let mangaRequest = ScrapeRequest(
                url: match.mangadexUrl,
                sourceKey: "mangadex",
                cookies: [],
                userAgent: original.userAgent,
                contentType: "comic",
                pageTitle: pendingPageTitle,
                previousSource: original.sourceKey,
                previousSourceUrl: original.url,
                matchConfidence: match.confidence
            )
            if let job = await submitAndHandle(mangaRequest) {
                modelContext.insert(job)
            }
        }
    }

    /// Called when the user taps "Keep <source>" in the match dialog.
    func declineMatch(modelContext: ModelContext) {
        guard let original = pendingOriginalRequest else { return }
        matchProposal = nil
        Task {
            let retry = ScrapeRequest(
                url: original.url,
                sourceKey: original.sourceKey,
                cookies: original.cookies,
                userAgent: original.userAgent,
                contentType: original.contentType,
                pageTitle: original.pageTitle,
                skipMatch: true
            )
            if let job = await submitAndHandle(retry) {
                modelContext.insert(job)
            }
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
        let path = url.path
        switch selectedSource {
        case .nhentai:
            canScrape = path.contains("/g/")
        case .toongod:
            canScrape = path.contains("/manga/") || path.contains("/webtoon/")
        case .hentai20:
            canScrape = path.contains("/manga/")
        case .mangadex:
            canScrape = path.contains("/title/")
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
        case .nhentai: homeURL = URL(string: "https://nhentai.net")!
        case .toongod: homeURL = URL(string: "https://www.toongod.org")!
        case .hentai20: homeURL = URL(string: "https://hentai20.io")!
        case .mangadex: homeURL = URL(string: "https://mangadex.org")!
        }
        webView?.load(URLRequest(url: homeURL))
        addressBarText = homeURL.absoluteString
    }
}

// MARK: - WebView

struct ComicWebViewRepresentable: UIViewRepresentable {
    let viewModel: ComicBrowserViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // Block popups — prevent ad windows from opening
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator  // Handle JS alerts/confirms
        webView.allowsBackForwardNavigationGestures = true
        viewModel.webView = webView
        ContentBlocker.shared.apply(to: webView)
        webView.load(URLRequest(url: viewModel.sourceURL))
        context.coordinator.loadedSource = viewModel.selectedSource

        // Observe loading progress
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
        // SPA support (AST-30): MangaDex uses client-side routing, so didFinish
        // doesn't fire on /title/ navigation. Observe webView.url directly.
        context.coordinator.urlObservation = webView.observe(\.url) { webView, _ in
            Task { @MainActor in
                let url = webView.url
                viewModel.currentURL = url
                viewModel.addressBarText = url?.absoluteString ?? ""
                if let url { viewModel.savedURLs[viewModel.selectedSource] = url }
                viewModel.evaluateCanScrape(url: url)
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
        let viewModel: ComicBrowserViewModel
        var loadedSource: ComicSource
        var progressObservation: NSKeyValueObservation?
        var loadingObservation: NSKeyValueObservation?
        var urlObservation: NSKeyValueObservation?
        var historyObservations: [NSKeyValueObservation] = []

        init(viewModel: ComicBrowserViewModel) {
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

        // MARK: - Navigation Policy

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // Block popup-style navigations (target=_blank ads)
            if navigationAction.navigationType == .other && navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }

            guard let host = navigationAction.request.url?.host?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            // Secure domain check — require exact match or subdomain (dot prefix)
            let allowed = viewModel.allowedDomains.contains { domain in
                host == domain || host.hasSuffix("." + domain)
            }
            // These sites are ad-heavy, so other domains stay blocked; say so
            // instead of leaving a tapped link apparently broken.
            if !allowed && navigationAction.navigationType == .linkActivated {
                viewModel.showToast(ScrapeToast(message: "Blocked a link to another site", isSuccess: false))
            }
            decisionHandler(allowed ? .allow : .cancel)
        }

        // MARK: - Navigation Events

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.currentURL = webView.url
            viewModel.addressBarText = webView.url?.absoluteString ?? ""
            if let url = webView.url {
                viewModel.savedURLs[viewModel.selectedSource] = url
            }
            viewModel.evaluateCanScrape(url: webView.url)
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward

            // Auto-harvest cookies
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
            // Ignore cancelled navigations (user tapped link while loading)
            guard nsError.code != NSURLErrorCancelled else { return }
            viewModel.showToast(ScrapeToast(message: "Page failed: \(nsError.localizedDescription)", isSuccess: false))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            viewModel.showToast(ScrapeToast(message: "Cannot load page", isSuccess: false))
        }

        // MARK: - WKUIDelegate — JS Alerts/Confirms/Prompts

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable () -> Void
        ) {
            // Silently dismiss — these are almost always ad-related on these sites
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            completionHandler(false)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (String?) -> Void
        ) {
            completionHandler(nil)
        }

        // Block popup windows (ads opening new windows)
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Deny all popup windows — return nil to block
            return nil
        }
    }
}

private struct MatchProposalIdentifiable: Identifiable {
    let payload: MangaDexMatchPayload
    var id: String { payload.mangaId }
}
