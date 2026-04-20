import Foundation
import Core

public actor APIClient {
    public static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let urlRequest = try endpoint.urlRequest()
        let method = urlRequest.httpMethod ?? "GET"
        let path = urlRequest.url?.path ?? "?"
        let start = CFAbsoluteTimeGetCurrent()

        AstralLogger.network("\(method) \(path) →")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            AstralLogger.error("\(method) \(path) — network error: \(error.localizedDescription) (\(ms)ms)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            AstralLogger.error("\(method) \(path) — invalid response (not HTTP)")
            throw APIError.invalidResponse
        }

        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let status = httpResponse.statusCode

        switch status {
        case 200...299:
            AstralLogger.network("\(method) \(path) → \(status) (\(ms)ms, \(data.count)B)")
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                AstralLogger.error("\(method) \(path) — decode failed: \(error)\nBody: \(preview)")
                throw error
            }
        case 428:
            AstralLogger.warning("\(method) \(path) → 428 cookie refresh needed (\(ms)ms)")
            throw APIError.cookieRefreshNeeded
        case 404:
            AstralLogger.warning("\(method) \(path) → 404 not found (\(ms)ms)")
            throw APIError.notFound
        case 429:
            AstralLogger.warning("\(method) \(path) → 429 rate limited (\(ms)ms)")
            throw APIError.rateLimited
        case 500...599:
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            AstralLogger.error("\(method) \(path) → \(status) server error (\(ms)ms)\n\(body)")
            throw APIError.serverError(status)
        default:
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            AstralLogger.error("\(method) \(path) → \(status) (\(ms)ms)\n\(body)")
            throw APIError.httpError(status)
        }
    }

    public func requestVoid(_ endpoint: Endpoint) async throws {
        let urlRequest = try endpoint.urlRequest()
        let method = urlRequest.httpMethod ?? "GET"
        let path = urlRequest.url?.path ?? "?"
        let start = CFAbsoluteTimeGetCurrent()

        AstralLogger.network("\(method) \(path) →")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            AstralLogger.error("\(method) \(path) — invalid response")
            throw APIError.invalidResponse
        }

        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let status = httpResponse.statusCode

        guard (200...299).contains(status) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            AstralLogger.error("\(method) \(path) → \(status) (\(ms)ms)\n\(body)")
            if status == 428 { throw APIError.cookieRefreshNeeded }
            throw APIError.httpError(status)
        }

        AstralLogger.network("\(method) \(path) → \(status) (\(ms)ms)")
    }

    /// AST-30 — submits a scrape request and decodes either a job-created or
    /// match-proposed response based on body shape. Both come back as 2xx.
    public func submitScrape(_ request: ScrapeRequest) async throws -> ScrapeOutcome {
        let endpoint = Endpoint.initiateScrape(request)
        let urlRequest = try endpoint.urlRequest()
        let method = urlRequest.httpMethod ?? "POST"
        let path = urlRequest.url?.path ?? "?"
        let start = CFAbsoluteTimeGetCurrent()

        AstralLogger.network("\(method) \(path) →")

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let status = httpResponse.statusCode

        switch status {
        case 503:
            throw APIError.serverError(503)
        case 200...299:
            AstralLogger.network("\(method) \(path) → \(status) (\(ms)ms)")
            // Try to decode the match envelope first; on failure, fall back
            // to the standard ScrapeJobResponse.
            if let match = try? decoder.decode(ScrapeMatchResponse.self, from: data) {
                return .matchProposed(match.match)
            }
            let job = try decoder.decode(ScrapeJobResponse.self, from: data)
            return .jobCreated(job)
        case 428:
            throw APIError.cookieRefreshNeeded
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(status)
        default:
            throw APIError.httpError(status)
        }
    }
}

public enum APIError: LocalizedError, Sendable {
    case invalidResponse
    case cookieRefreshNeeded
    case notFound
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case encodingFailed
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .cookieRefreshNeeded: "Browser refresh needed"
        case .notFound: "Resource not found"
        case .rateLimited: "Rate limited — try again later"
        case .serverError(let code): "Server error (\(code))"
        case .httpError(let code): "HTTP error (\(code))"
        case .encodingFailed: "Failed to encode request"
        case .invalidURL: "Invalid URL"
        }
    }
}
