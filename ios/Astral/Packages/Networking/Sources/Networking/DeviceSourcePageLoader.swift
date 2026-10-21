import Foundation
import WebKit

/// One foreground top-level navigation at a time, sharing the phone's website data.
@MainActor
public final class DeviceSourcePageLoader: NSObject, WKNavigationDelegate {
    public let webView: WKWebView
    private var pending: CheckedContinuation<Void, Error>?
    private var activeNavigation: WKNavigation?
    private var timeout: Task<Void, Never>?
    public override init() {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .default(); config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        super.init(); webView.navigationDelegate = self
    }
    public func load(_ url: URL) async throws {
        try Task.checkCancellation()
        guard pending == nil else { throw PageError.message("Another chapter from this source is opening. Wait and retry.") }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(45)); finish(PageError.message("The source took too long. Open the chapter in Add and retry.")); webView.stopLoading() } catch {}
                }
                activeNavigation = webView.load(URLRequest(url: url))
            }
        } onCancel: { Task { @MainActor in self.finish(CancellationError()); self.webView.stopLoading() } }
    }
    private func finish(_ error: Error? = nil) {
        timeout?.cancel(); timeout = nil; activeNavigation = nil
        let continuation = pending; pending = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if navigation === activeNavigation { finish() } }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === activeNavigation { finish(error) } }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if navigation === activeNavigation { finish(error) } }
    private enum PageError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { text } else { nil } } }
}
