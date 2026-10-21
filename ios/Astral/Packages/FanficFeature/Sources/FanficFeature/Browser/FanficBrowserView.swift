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
    @State private var readImported = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fanficNavigation) private var fanficNavigation

    var body: some View {
        VStack(spacing: 0) {

            if viewModel.isScraping {
                HStack { Text("Importing on this device…").font(.callout); Spacer(); Button("Cancel") { cancelImport() } }.padding(.horizontal, 16)
            } else if let importedWork {
                HStack {
                    Text("Saved: " + importedWork.title).font(.callout).lineLimit(1)
                    Button("Read now") { readImported = true }
                    Button("View in library") { fanficNavigation?.activeSection = .library }
                    Button("Dismiss", systemImage: "xmark") { self.importedWork = nil }.labelStyle(.iconOnly)
                }.padding(12)
            }
            Text("Open a story, then tap Import. Chapters are saved on this device. Keep Astral open until the import finishes.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
            // Loading progress bar
            if viewModel.isLoading {
                ProgressView(value: viewModel.loadProgress)
                    .tint(AstralColors.gold)
                    .scaleEffect(x: 1, y: 0.5)
                    .padding(.horizontal, 16)
            }

            // Browser action bar
            HStack(spacing: 10) {
                Button(action: viewModel.goBack) {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!viewModel.canGoBack)
                .foregroundColor(viewModel.canGoBack ? .primary : .secondary)

                Button(action: viewModel.goForward) {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!viewModel.canGoForward)
                .foregroundColor(viewModel.canGoForward ? .primary : .secondary)

                Button(action: viewModel.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundColor(.primary)

                // Address bar with cookie indicator
                HStack(spacing: 4) {
                    if viewModel.cookieCount > 0 {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AstralColors.success)
                    }
                    TextField("Enter URL", text: $viewModel.addressBarText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .onSubmit { viewModel.navigateToAddress() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AstralColors.elevated, in: RoundedRectangle(cornerRadius: 6))

                Button(action: {
                    importTask = Task { @MainActor in
                        if [.ao3, .ffnet].contains(viewModel.selectedSource) {
                            guard let webView = viewModel.webView else { return }
                            viewModel.isScraping = true
                            defer { viewModel.isScraping = false }
                            do {
                                importedWork = try await AO3ImportService.shared.importWork(from: webView, modelContext: modelContext, onCancel: { cancelImport() })
                                fanficNavigation?.ao3WorkURL = nil
                            } catch is CancellationError {
                                // Leaving an import doesn't create a partial library entry.
                            } catch {
                                importError = error.localizedDescription
                            }
                        } else if let job = await viewModel.extractCookiesAndScrape() {
                            modelContext.insert(job)
                        }
                    }
                }) {
                    if viewModel.isScraping {
                        ProgressView()
                            .tint(AstralColors.gold)
                            .scaleEffect(0.75)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(viewModel.canScrape ? AstralColors.gold : .secondary)
                    }
                }
                .disabled(!viewModel.canScrape || viewModel.isScraping || viewModel.isLoading)
                .buttonStyle(PressButtonStyle(scale: 0.85))
                .accessibilityLabel(viewModel.selectedSource == .ao3 ? "Import AO3 work" : "Import FFNet story")
                .accessibilityIdentifier("fanfic.browser.import")

                Button {
                    viewModel.resetToSourceHome()
                } label: {
                    Image(systemName: "house")
                        .foregroundColor(.primary)
                }
            }
            .disabled(viewModel.isScraping)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // WebView
            FanficWebViewRepresentable(viewModel: viewModel)
                .allowsHitTesting(!viewModel.isScraping)
        }
        .background(AstralColors.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { sourceMenu }
            ToolbarItem(placement: .topBarTrailing) { fileImportButton }
        }
        .fileImporter(isPresented: $showFileImport, allowedContentTypes: [.plainText]) { result in
            do {
                let story = try LocalFileImportService.importText(result.get(), context: modelContext)
                fileImportMessage = "Saved: " + story.title + ". Open it from Library or Activity."
            } catch { fileImportMessage = error.localizedDescription }
        }
        .alert("File import", isPresented: Binding(get: { fileImportMessage != nil }, set: { if !$0 { fileImportMessage = nil } })) {
            Button("OK") { fileImportMessage = nil }
        } message: { Text(fileImportMessage ?? "") }

        .navigationTitle("Add fan fiction").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $readImported) {
            if let importedWork {
                ImportedFanficReader(fanfic: importedWork)
            }
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
        .overlay(alignment: .bottom) {
            if let toast = viewModel.scrapeToast {
                ToastView(toast.message, isSuccess: toast.isSuccess)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
            }
        }
        .animation(AstralAnimation.smooth, value: viewModel.scrapeToast?.message)
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(FanficSource.allCases, id: \.self) { source in
                Button {
                    viewModel.selectedSource = source
                } label: {
                    Label(sourceLabel(source), systemImage: viewModel.selectedSource == source ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(sourceLabel(viewModel.selectedSource))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel("Choose source")
        .accessibilityValue(sourceLabel(viewModel.selectedSource))
        .disabled(viewModel.isScraping)
    }

    private var fileImportButton: some View {
        Button("Import text file", systemImage: "doc.badge.plus") { showFileImport = true }
            .labelStyle(.iconOnly)
            .accessibilityHint("Choose a UTF-8 text file to save as a single chapter.")
            .accessibilityIdentifier("fanfic.browser.fileImport")
            .disabled(viewModel.isScraping)
    }

    private func sourceLabel(_ source: FanficSource) -> String {
        switch source {
        case .ao3: "AO3"
        case .ffnet: "FFNet"
        }
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

    var allowedDomains: [String] {
        switch selectedSource {
        case .ao3: return ["archiveofourown.org"]
        case .ffnet: return ["fanfiction.net"]
        }
    }

    func navigateToAddress() {
        var text = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text) else { return }
        webView?.load(URLRequest(url: url))
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

        init(viewModel: FanficBrowserViewModel) {
            self.viewModel = viewModel
            self.loadedSource = viewModel.selectedSource
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
