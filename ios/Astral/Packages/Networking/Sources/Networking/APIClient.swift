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
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try decoder.decode(T.self, from: data)
        case 428:
            throw APIError.cookieRefreshNeeded
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    public func requestVoid(_ endpoint: Endpoint) async throws {
        let urlRequest = try endpoint.urlRequest()
        let (_, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 428 {
                throw APIError.cookieRefreshNeeded
            }
            throw APIError.httpError(httpResponse.statusCode)
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
