import Foundation

public struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let totalPages: Int
    public let hasNext: Bool
}

public struct AuthorResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
}

public struct HealthResponse: Codable, Sendable {
    public let status: String
}
