import Foundation
import Core

public struct Endpoint: Sendable {
    public let method: HTTPMethod
    public let path: String
    public let queryItems: [URLQueryItem]?
    public let body: (any Encodable & Sendable)?

    public init(
        method: HTTPMethod = .get,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable & Sendable)? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
    }

    func urlRequest() throws -> URLRequest {
        guard var components = URLComponents(string: AppConfig.apiBaseURL + path) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - Comic Endpoints

public extension Endpoint {
    static func comics(page: Int = 1, pageSize: Int = 200, sort: String? = nil) -> Endpoint {
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)"),
        ]
        if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
        return Endpoint(path: "/comics", queryItems: items)
    }

    static func comicDetail(id: UUID) -> Endpoint {
        Endpoint(path: "/comics/\(id)")
    }

    static func chapterPages(comicId: UUID, chapterId: UUID) -> Endpoint {
        Endpoint(path: "/comics/\(comicId)/chapters/\(chapterId)/pages")
    }

    static func updateComic(id: UUID, body: ComicUpdateRequest) -> Endpoint {
        Endpoint(method: .patch, path: "/comics/\(id)", body: body)
    }

    static func deleteComic(id: UUID) -> Endpoint {
        Endpoint(method: .delete, path: "/comics/\(id)")
    }

    static func permanentDeleteComic(id: UUID) -> Endpoint {
        Endpoint(method: .delete, path: "/comics/\(id)/permanent")
    }

    static func archiveComic(id: UUID) -> Endpoint {
        Endpoint(method: .post, path: "/comics/\(id)/archive")
    }

    static func unarchiveComic(id: UUID) -> Endpoint {
        Endpoint(method: .post, path: "/comics/\(id)/unarchive")
    }
}

// MARK: - Fanfic Endpoints

public extension Endpoint {
    static func fanfics(
        page: Int = 1,
        pageSize: Int = 200,
        fandom: String? = nil,
        rating: String? = nil,
        completionStatus: String? = nil,
        sort: String? = nil
    ) -> Endpoint {
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)"),
        ]
        if let fandom { items.append(URLQueryItem(name: "fandom", value: fandom)) }
        if let rating { items.append(URLQueryItem(name: "rating", value: rating)) }
        if let completionStatus { items.append(URLQueryItem(name: "completion_status", value: completionStatus)) }
        if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
        return Endpoint(path: "/fanfic", queryItems: items)
    }

    static func fanficDetail(id: UUID) -> Endpoint {
        Endpoint(path: "/fanfic/\(id)")
    }

    static func fanficChapter(fanficId: UUID, chapterId: UUID) -> Endpoint {
        Endpoint(path: "/fanfic/\(fanficId)/chapters/\(chapterId)")
    }

    static func deleteFanfic(id: UUID) -> Endpoint {
        Endpoint(method: .delete, path: "/fanfic/\(id)")
    }

    static func permanentDeleteFanfic(id: UUID) -> Endpoint {
        Endpoint(method: .delete, path: "/fanfic/\(id)/permanent")
    }
}

// MARK: - Author Endpoints

public extension Endpoint {
    static func authorDetail(id: UUID) -> Endpoint {
        Endpoint(path: "/authors/\(id)")
    }
}

// MARK: - Scrape Endpoints

public extension Endpoint {
    static func initiateScrape(_ request: ScrapeRequest) -> Endpoint {
        let path = request.contentType == "comic" ? "/scrape/comic" : "/scrape/fanfic"
        return Endpoint(method: .post, path: path, body: request)
    }

    static func scrapeStatus(jobId: UUID) -> Endpoint {
        Endpoint(path: "/scrape/\(jobId)")
    }

    static func retryScrape(jobId: UUID) -> Endpoint {
        Endpoint(method: .post, path: "/scrape/\(jobId)/retry")
    }

    static func deltaUpdate(storyId: UUID) -> Endpoint {
        Endpoint(method: .post, path: "/scrape/\(storyId)/update")
    }

    static func allScrapeJobs(page: Int = 1, pageSize: Int = 20) -> Endpoint {
        Endpoint(path: "/scrape", queryItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)"),
        ])
    }

    static func scrapeJobLogs(jobId: UUID) -> Endpoint {
        Endpoint(path: "/scrape/\(jobId)/logs")
    }
}

// MARK: - Progress Endpoints

public extension Endpoint {
    static func updateComicProgress(storyId: UUID, body: ComicProgressRequest) -> Endpoint {
        Endpoint(method: .put, path: "/progress/comic/\(storyId)", body: body)
    }

    static func updateFanficProgress(storyId: UUID, body: FanficProgressRequest) -> Endpoint {
        Endpoint(method: .put, path: "/progress/fanfic/\(storyId)", body: body)
    }

    static func getProgress(type: String, storyId: UUID) -> Endpoint {
        Endpoint(path: "/progress/\(type)/\(storyId)")
    }

    /// Fetch all progress records for a content type in one call.
    /// Used by library ViewModels on refresh to restore reading position after a SwiftData wipe.
    static func allProgress(contentType: String) -> Endpoint {
        Endpoint(path: "/progress", queryItems: [
            URLQueryItem(name: "content_type", value: contentType),
        ])
    }
}

// MARK: - Health

public extension Endpoint {
    static var health: Endpoint {
        Endpoint(path: "/health")
    }
}
