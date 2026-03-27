import SwiftUI
import WebKit
import Core
import DesignSystem
import Networking

struct FanficBrowserView: View {
    @State private var viewModel = FanficBrowserViewModel()

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
                
                Spacer(minLength: 8)
                
                Text(viewModel.currentURL?.absoluteString ?? viewModel.sourceURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer(minLength: 8)
                
                Button(action: {
                    Task { await viewModel.extractCookiesAndScrape() }
                }) {
                    Image(systemName: "arrow.down.circle")
                }
                .foregroundColor(viewModel.canScrape ? .primary : .secondary)
                .disabled(!viewModel.canScrape)
                
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
    var currentURL: URL?
    var webView: WKWebView?
    var savedURLs: [FanficSource: URL] = [:]
    var canGoBack = false
    var canGoForward = false

    var sourceURL: URL {
        if let saved = savedURLs[selectedSource] {
            return saved
        }
        switch selectedSource {
        case .ao3: return URL(string: "https://archiveofourown.org")!
        case .ffnet: return URL(string: "https://www.fanfiction.net")!
        }
    }

    func extractCookiesAndScrape() async {
        guard let webView, let url = currentURL else { return }

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
            let job: ScrapeJobResponse = try await APIClient.shared.request(
                .initiateScrape(request)
            )
            _ = job
        } catch {
            // TODO: Handle error
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.currentURL = webView.url
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
