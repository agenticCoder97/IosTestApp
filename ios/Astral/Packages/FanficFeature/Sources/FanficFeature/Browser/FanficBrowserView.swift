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

            // WebView
            FanficWebViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)

            if viewModel.canScrape {
                GoldButton("Scrape", icon: "arrow.down.circle") {
                    Task { await viewModel.extractCookiesAndScrape() }
                }
                .padding()
            }
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

    var sourceURL: URL {
        switch selectedSource {
        case .ao3: URL(string: "about:blank")!
        case .ffnet: URL(string: "about:blank")!
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
