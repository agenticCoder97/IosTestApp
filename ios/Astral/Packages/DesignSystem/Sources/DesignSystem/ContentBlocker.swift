import WebKit

/// Compiles and caches a WKContentRuleList that blocks ads and trackers.
/// Call `ContentBlocker.shared.apply(to:)` in your WebView's makeUIView.
@MainActor
public final class ContentBlocker {
    public static let shared = ContentBlocker()

    private var compiledList: WKContentRuleList?
    private var isCompiling = false

    private init() {}

    /// Applies the content blocker to the given WKWebView.
    /// Compiles rules asynchronously on first call; subsequent calls are instant.
    public func apply(to webView: WKWebView) {
        if let list = compiledList {
            webView.configuration.userContentController.add(list)
            return
        }
        guard !isCompiling else { return }
        isCompiling = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "AstralAdBlock_v2",
            encodedContentRuleList: Self.rulesJSON
        ) { [weak self] list, error in
            guard let self else { return }
            Task { @MainActor in
                self.isCompiling = false
                if let list {
                    self.compiledList = list
                    webView.configuration.userContentController.add(list)
                }
            }
        }
    }

    // MARK: - Rules JSON

    /// Apple Content Blocker rules targeting the ad/tracker domains most
    /// frequently encountered on comic and fanfic reading sites.
    private static let rulesJSON = """
    [
      {"trigger":{"url-filter":"\\\\.googlesyndication\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.doubleclick\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.googleadservices\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"pagead2\\\\.googlesyndication\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.adnxs\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.pubmatic\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.rubiconproject\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.openx\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.criteo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.taboola\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.outbrain\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.revcontent\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.amazon-adsystem\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.scorecardresearch\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.quantserve\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.moatads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.adsrvr\\\\.org","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.casalemedia\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.media\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.mgid\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.trafficjunky\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.exoclick\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.juicyads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.hilltopads\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.popads\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.popcash\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.propellerads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.adsterra\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.clickadu\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.ero-advertising\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.adspyglass\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.valueclick\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.zedo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.yieldmo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.lijit\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.sharethrough\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.triplelift\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.gumgum\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.teads\\\\.tv","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.spotxchange\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.spotx\\\\.tv","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*[/=?&](?:ad|ads|advert|advertisement|banner|popup|popunder|interstitial)[/=?&_.-]","load-type":["third-party"],"resource-type":["script","raw"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[id*='google_ads'],[id*='doubleclick'],[class*='ad-unit'],[class*='ad-slot'],[class*='adsbygoogle'],[id*='aswift'],[class*='popup-ad'],[class*='popunder'],[class*='overlay-ad']"}}
    ]
    """
}
