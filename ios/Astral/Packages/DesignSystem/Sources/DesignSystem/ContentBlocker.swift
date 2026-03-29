import WebKit

/// Compiles and caches WKContentRuleLists for ad/tracker blocking, and injects
/// a MutationObserver-based JS script to remove ad DOM elements that slip through.
@MainActor
public final class ContentBlocker {
    public static let shared = ContentBlocker()

    private var compiledLists: [WKContentRuleList] = []
    private var isCompiling = false

    private init() {}

    /// Pre-compile rules on app launch so they're ready before the first page load.
    public func precompile() {
        guard compiledLists.isEmpty, !isCompiling else { return }
        isCompiling = true

        guard let store = WKContentRuleListStore.default() else { isCompiling = false; return }
        var pending = Self.ruleSets.count

        for (idx, ruleJSON) in Self.ruleSets.enumerated() {
            store.compileContentRuleList(
                forIdentifier: "AstralAdBlock_v5_\(idx)",
                encodedContentRuleList: ruleJSON
            ) { [weak self] list, error in
                guard let self else { return }
                Task { @MainActor in
                    if let list { self.compiledLists.append(list) }
                    pending -= 1
                    if pending == 0 { self.isCompiling = false }
                }
            }
        }
    }

    /// Applies all compiled content blocker lists + JS ad remover to the given WKWebView.
    public func apply(to webView: WKWebView) {
        let controller = webView.configuration.userContentController

        if !compiledLists.isEmpty {
            for list in compiledLists {
                controller.add(list)
            }
        } else if !isCompiling {
            precompile()
        }

        // Inject JS cosmetic ad remover — catches DOM-injected ads that bypass network rules
        let script = WKUserScript(
            source: Self.cosmeticRemoverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(script)
    }

    // MARK: - JS Cosmetic Ad Remover

    /// MutationObserver that removes known ad containers as they appear in the DOM.
    /// Targets ExoClick (nhentai), generic ad wrappers, overlay/popup ads.
    private static let cosmeticRemoverJS = """
    (function() {
        'use strict';
        const adSelectors = [
            '[class*="exo-"]', '[id^="exo_"]', '.exo-container',
            '[class*="adsbygoogle"]', '[id*="google_ads"]',
            '[class*="ad-unit"]', '[class*="ad-slot"]', '[class*="ad-container"]',
            '[class*="ad-banner"]', '[id*="ad-container"]', '[id*="advert"]',
            '[class*="popup-ad"]', '[class*="popunder"]', '[class*="overlay-ad"]',
            '[class*="sticky-ad"]', '[class*="floating-ad"]', '[class*="popup-overlay"]',
            '[class*="advert-wrapper"]', '[class*="interstitial"]',
            '[class*="wp-manga-alert-popup"]', '[id*="wps-popup"]',
            '[class*="notif-permission"]', '[class*="push-notification"]',
            'div[style*="position:fixed"][style*="z-index"]',
            'div[style*="position: fixed"][style*="z-index"]',
            'iframe[src*="exoclick"]', 'iframe[src*="juicyads"]',
            'iframe[src*="trafficjunky"]', 'iframe[src*="popads"]',
            'iframe[src*="adsterra"]', 'iframe[src*="clickadu"]',
            'a[href*="exoclick.com"]', 'a[href*="trafficjunky"]',
            'a[href*="juicyads"]', 'a[href*="popads.net"]',
            'div[id*="underplayer"]', 'div[id*="overplayer"]',
        ];
        const selectorString = adSelectors.join(',');

        function removeAds() {
            document.querySelectorAll(selectorString).forEach(el => {
                el.remove();
            });
        }

        // Initial pass
        removeAds();

        // Watch for dynamically injected ads
        const observer = new MutationObserver(removeAds);
        observer.observe(document.body || document.documentElement, {
            childList: true, subtree: true
        });

        // Also remove after short delays (some ads inject with setTimeout)
        setTimeout(removeAds, 1000);
        setTimeout(removeAds, 3000);
        setTimeout(removeAds, 5000);
    })();
    """

    // MARK: - Network Blocking Rules (split into chunks for compilation limits)

    /// Multiple rule sets compiled as separate WKContentRuleLists.
    /// Split to stay under per-list compilation limits.
    private static let ruleSets: [String] = [networkRules1, networkRules2, cssRules]

    // MARK: Rule Set 1 — Major ad networks
    private static let networkRules1 = """
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
      {"trigger":{"url-filter":"\\\\.yieldmo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.lijit\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.sharethrough\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.triplelift\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.gumgum\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.teads\\\\.tv","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.spotxchange\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.spotx\\\\.tv","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.imasdk\\\\.googleapis\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.smartadserver\\\\.com","load-type":["third-party"]},"action":{"type":"block"}}
    ]
    """

    // MARK: Rule Set 2 — Adult ad networks + trackers + popups
    private static let networkRules2 = """
    [
      {"trigger":{"url-filter":"\\\\.trafficjunky\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.exoclick\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.exosrv\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.exdynsrv\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.realsrv\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.magsrv\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.juicyads\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.hilltopads\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.popads\\\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.popcash\\\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.propellerads\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.adsterra\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.clickadu\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.ero-advertising\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.adspyglass\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.tsyndicate\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.a-ads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.bidvertiser\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.plugrush\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.trafficstars\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.ad-maven\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.admaven\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.adxxx\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.clickaine\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.cpmstar\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.galaksion\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.frtyd\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.ntvsrv\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.wpadmngr\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.webpushr\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.hotjar\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.onesignal\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.pushwoosh\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.mixpanel\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.segment\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.cookiebot\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.disqus\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.betterads\\\\.org","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.buysellads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.valueclick\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.zedo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.fastclick\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.serving-sys\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.richaudience\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.nativery\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.vdo\\\\.ai","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.vidoomy\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.carbonads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"\\\\.mouseflow\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*[/=?&](?:ad|ads|advert|banner|popup|popunder|interstitial)[/=?&_.-]","load-type":["third-party"],"resource-type":["script","raw"]},"action":{"type":"block"}}
    ]
    """

    // MARK: Rule Set 3 — CSS display:none for ad containers
    private static let cssRules = """
    [
      {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[id*='google_ads'],[id*='doubleclick'],[class*='ad-unit'],[class*='ad-slot'],[class*='adsbygoogle'],[id*='aswift'],[class*='popup-ad'],[class*='popunder'],[class*='overlay-ad'],[class*='sticky-ad'],[class*='floating-ad'],[class*='popup-overlay'],[id*='ad-container'],[class*='ad-container'],[class*='ad-banner'],[class*='advert-wrapper'],[id*='advert'],[class*='interstitial'],[class*='wp-manga-alert-popup'],[id*='wps-popup'],[class*='notif-permission'],[class*='push-notification'],[class*='exo-'],[id^='exo_'],[class*='exo-container']"}}
    ]
    """
}
