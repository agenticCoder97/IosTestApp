import SwiftUI
import SwiftData
import WebKit
import Core
import DesignSystem
import Networking

struct ComicBrowserView: View {
    @State private var viewModel = ComicBrowserViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Source dropdown
            HStack {
                Menu {
                    ForEach(ComicSource.allCases, id: \.self) { source in
                        Button {
                            viewModel.selectedSource = source
                        } label: {
                            Label(source.rawValue, systemImage: viewModel.selectedSource == source ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                        Text(viewModel.selectedSource.rawValue)
                            .font(AstralTypography.bodyMedium)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AstralColors.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AstralColors.elevated, in: Capsule())
                }
                .tint(AstralColors.gold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

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
                    Task {
                        if let job = await viewModel.extractCookiesAndScrape() {
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
                .disabled(!viewModel.canScrape || viewModel.isScraping)
                .buttonStyle(PressButtonStyle(scale: 0.85))

                Button {
                    viewModel.resetToSourceHome()
                } label: {
                    Image(systemName: "house")
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // WebView
            ComicWebViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(AstralColors.background)
        .overlay(alignment: .bottom) {
            if let toast = viewModel.scrapeToast {
                ToastView(toast.message, isSuccess: toast.isSuccess)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
            }
        }
        .animation(AstralAnimation.smooth, value: viewModel.scrapeToast?.message)
    }
}

@MainActor @Observable
final class ComicBrowserViewModel {
    var selectedSource: ComicSource = .hentai20
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

        let store = await webView.configuration.websiteDataStore.httpCookieStore
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
            contentType: "comic"
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

        init(viewModel: ComicBrowserViewModel) {
            self.viewModel = viewModel
            self.loadedSource = viewModel.selectedSource
        }

        // MARK: - Navigation Policy

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
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
            completionHandler: @escaping () -> Void
        ) {
            // Silently dismiss — these are almost always ad-related on these sites
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(false)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
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
