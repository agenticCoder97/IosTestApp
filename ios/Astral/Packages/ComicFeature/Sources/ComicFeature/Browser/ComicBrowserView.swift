import SwiftUI
import WebKit
import Core
import DesignSystem
import Networking

struct ComicBrowserView: View {
    @State private var viewModel = ComicBrowserViewModel()

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

            // WebView
            WebViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)

            // Scrape button (shown when on a story page)
            if viewModel.canScrape {
                GoldButton("Scrape", icon: "arrow.down.circle") {
                    Task { await viewModel.extractCookiesAndScrape() }
                }
                .padding()
            }
        }
        .background(AstralColors.background)
    }
}

@MainActor @Observable
final class ComicBrowserViewModel {
    var selectedSource: ComicSource = .nhentai
    var canScrape = false
    var currentURL: URL?
    var webView: WKWebView?

    var sourceURL: URL {
        switch selectedSource {
        case .nhentai: URL(string: "about:blank")!
        case .toongod: URL(string: "about:blank")!
        case .hentai20: URL(string: "about:blank")!
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
            contentType: "comic"
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
}

struct WebViewRepresentable: UIViewRepresentable {
    let viewModel: ComicBrowserViewModel

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
        let viewModel: ComicBrowserViewModel

        init(viewModel: ComicBrowserViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.currentURL = webView.url

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
