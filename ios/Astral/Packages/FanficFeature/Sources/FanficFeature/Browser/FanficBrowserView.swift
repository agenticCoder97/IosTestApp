import SwiftUI
import SwiftData
import WebKit
import Core
import DesignSystem
import Networking

struct FanficBrowserView: View {
    @State private var viewModel = FanficBrowserViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Source picker
            Picker("Source", selection: $viewModel.selectedSource) {
                ForEach(FanficSource.allCases, id: \.self) { source in
                    Text(sourceLabel(source)).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Unified Browser Action Bar
            HStack(spacing: 12) {
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
                
                TextField("Enter URL", text: $viewModel.addressBarText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onSubmit { viewModel.navigateToAddress() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(AstralColors.elevated, in: RoundedRectangle(cornerRadius: 6))
                    .lineLimit(1)
                
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
                
                Button(action: viewModel.openInSafari) {
                    Image(systemName: "safari")
                }
                .foregroundColor(viewModel.currentURL != nil ? .primary : .secondary)
                .disabled(viewModel.currentURL == nil)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // WebView
            FanficWebViewRepresentable(viewModel: viewModel)
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

    private func sourceLabel(_ source: FanficSource) -> String {
        switch source {
        case .ao3: "AO3"
        case .ffnet: "FFNet"
        }
    }
}

@MainActor @Observable
final class FanficBrowserViewModel {
    var selectedSource: FanficSource = .ao3
    var canScrape = false
    var isScraping = false
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
            showToast(ScrapeToast(message: "Scrape failed", isSuccess: false))
            return nil
        }
    }

    private func showToast(_ toast: ScrapeToast) {
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
        case .ao3:
            canScrape = path.contains("/works/")
        case .ffnet:
            canScrape = path.contains("/s/")
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func openInSafari() {
        if let url = currentURL ?? URL(string: sourceURL.absoluteString) {
            #if os(iOS)
            UIApplication.shared.open(url)
            #endif
        }
    }
}

struct FanficWebViewRepresentable: UIViewRepresentable {
    let viewModel: FanficBrowserViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        viewModel.webView = webView
        ContentBlocker.shared.apply(to: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: viewModel.sourceURL)
        if webView.url != viewModel.sourceURL {
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: FanficBrowserViewModel

        init(viewModel: FanficBrowserViewModel) {
            self.viewModel = viewModel
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let host = navigationAction.request.url?.host?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            let allowed = viewModel.allowedDomains.contains { host.hasSuffix($0) }
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
    }
}
