import Foundation

public struct CookieDTO: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let domain: String

    public init(name: String, value: String, domain: String) {
        self.name = name
        self.value = value
        self.domain = domain
    }
}
