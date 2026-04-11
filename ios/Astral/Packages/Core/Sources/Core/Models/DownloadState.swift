import Foundation

public enum DownloadState: String, Codable {
    case none
    case queued
    case downloading
    case failed
    case complete
}

public enum DownloadError: LocalizedError {
    case insufficientDiskSpace
    case fileValidationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace: return "Not enough storage space"
        case .fileValidationFailed(let reason): return "File validation failed: \(reason)"
        }
    }
}
