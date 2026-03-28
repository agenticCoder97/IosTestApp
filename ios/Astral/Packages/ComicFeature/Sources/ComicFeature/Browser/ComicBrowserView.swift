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
            // Source picker
            Picker("Source", selection: $viewModel.selectedSource) {
                ForEach(ComicSource.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
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

                Spacer(minLength: 8)

                Text(viewModel.currentURL?.absoluteString ?? viewModel.sourceURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

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
            WebViewRepresentable(viewModel: viewModel)
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
    var selectedSource: ComicSource = .nhentai
    var canScrape = false
    var isScraping = false
    var scrapeToast: ScrapeToast? = nil
    var currentURL: URL?
    var webView: WKWebView?
    var savedURLs: [ComicSource: URL] = [:]
    var canGoBack = false
    var canGoForward = false

    var sourceURL: URL {
        if let saved = savedURLs[selectedSource] {
            return saved
        }
        switch selectedSource {
        case .nhentai: return URL(string: "https://nhentai.net")!
        case .toongod: return URL(string: "https://www.toongod.com")!
        case .hentai20: return URL(string: "https://hentai20.io")!
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
            showToast(ScrapeToast(message: "Scrape queued", isSuccess: true))
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
        case .nhentai:
            canScrape = path.contains("/g/")
        case .toongod:
            canScrape = path.contains("/manga/") || path.contains("/webtoon/")
        case .hentai20:
            canScrape = path.contains("/manga/")
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

struct WebViewRepresentable: UIViewRepresentable {
    let viewModel: ComicBrowserViewModel

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
        let viewModel: ComicBrowserViewModel

        init(viewModel: ComicBrowserViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.currentURL = webView.url
            if let url = webView.url {
                viewModel.savedURLs[viewModel.selectedSource] = url
            }
            viewModel.evaluateCanScrape(url: webView.url)
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward

            // Auto-harvest cookies on every page load (architecture convention 9.2)
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
