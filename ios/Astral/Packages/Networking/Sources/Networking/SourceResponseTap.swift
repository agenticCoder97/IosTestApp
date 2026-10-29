import Foundation
import WebKit

/// Keeps copies of the API responses a source's own page receives. MangaFire signs
/// its API calls with tokens that only its scripts produce, so the importer lets
/// the site make its normal requests and reads what came back.
/// Nothing here computes, alters or replays a token.
@MainActor
public enum SourceResponseTap {
    /// Host → API paths worth keeping. Everything else on every other site is ignored.
    static let rules: [String: [String]] = [
        "mangafire.to": [#"^/api/titles/[^/]+$"#, #"^/api/titles/[^/]+/chapters$"#, #"^/api/chapters/\d+$"#],
    ]

    public struct Capture: Decodable, Sendable {
        public let path: String
        public let query: String
        public let status: Int
        public let body: String

        public func queryValue(_ name: String) -> String? {
            URLComponents(string: "https://source.invalid" + path + query)?.queryItems?.first { $0.name == name }?.value
        }
    }

    /// The tap runs in the page's own world, where the site's requests happen.
    public static func install(in controller: WKUserContentController) {
        guard let data = try? JSONEncoder().encode(rules), let json = String(data: data, encoding: .utf8) else { return }
        controller.addUserScript(WKUserScript(source: script.replacingOccurrences(of: "__RULES__", with: json),
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
    }

    /// Responses captured so far whose path matches `pattern`, oldest first.
    public static func captured(in webView: WKWebView, path pattern: String) async throws -> [Capture] {
        let value = try await webView.callAsyncJavaScript(
            "const re = new RegExp(pattern); return JSON.stringify((window.__astralTap || []).filter(e => re.test(e.path)));",
            arguments: ["pattern": pattern], in: nil, contentWorld: .page)
        guard let json = value as? String, let data = json.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([Capture].self, from: data)
    }

    /// A single-page app asks for its data after `didFinish`, so poll until it arrives.
    public static func wait(in webView: WKWebView, path pattern: String, timeout: Duration = .seconds(30),
                            where accept: (Capture) -> Bool = { _ in true }) async throws -> Capture {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let match = try await captured(in: webView, path: pattern).last(where: accept) {
                guard (200..<300).contains(match.status) else { throw TapError.status(match.status) }
                return match
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw TapError.timedOut
    }

    public enum TapError: LocalizedError {
        case timedOut, status(Int)
        public var errorDescription: String? {
            switch self {
            case .timedOut: "The source page didn't load its data. Open it in Add, complete any verification, then retry."
            case .status(let code): code == 429 ? "The source is limiting requests. Wait before retrying." : "The source returned HTTP \(code). Open it in Add, then retry."
            }
        }
    }

    private static let script = """
    (() => {
      const rules = __RULES__;
      const patterns = (rules[location.hostname.replace(/^www\\./, '')] || []).map(p => new RegExp(p));
      if (!patterns.length || window.__astralTap) return;
      const store = [];
      Object.defineProperty(window, '__astralTap', { value: store });
      const target = url => { try { const u = new URL(url, location.href); return u.origin === location.origin && patterns.some(p => p.test(u.pathname)) ? u : null; } catch { return null; } };
      const keep = (u, status, body) => {
        if (typeof body !== 'string' || body.length > 4000000) return;
        store.push({ path: u.pathname, query: u.search, status, body });
        if (store.length > 200) store.shift();
      };
      const fetch = window.fetch;
      window.fetch = function (input) {
        const u = target(typeof input === 'string' || input instanceof URL ? String(input) : input && input.url);
        const request = fetch.apply(this, arguments);
        if (u) request.then(r => r.clone().text().then(body => keep(u, r.status, body))).catch(() => {});
        return request;
      };
      const open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) { this.__astralTarget = target(url); return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function () {
        const u = this.__astralTarget;
        if (u) this.addEventListener('load', () => {
          const t = this.responseType;
          keep(u, this.status, t === '' || t === 'text' ? this.responseText : t === 'json' ? JSON.stringify(this.response) : null);
        });
        return send.apply(this, arguments);
      };
    })();
    """
}
