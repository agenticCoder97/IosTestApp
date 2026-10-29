import Foundation

/// Comic page bytes are either in the bounded reading view or saved explicitly.
/// Avoid a second, invisible disk cache outside the user's offline storage budget.
public enum SourceImageTransport {
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()
    public static func request(_ url: URL, referrer: String?) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        if let referrer, let source = URL(string: referrer), source.scheme == "https" {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
            let host = source.host ?? ""
            let key = ["toongod", "hentai20", "mangafire"].first { host.contains($0) } ?? "nhentai"
            if let agent = UserDefaults.standard.string(forKey: "reading.sourceUserAgent." + key) { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        }
        return request
    }
}
