import SwiftUI
import Core

/// Reusable thumbnail view — uses disk-cached image loading, falls back to a colored placeholder.
public struct StoryThumbnail: View {
    let path: String?
    let baseURL: String
    let title: String
    let icon: String
    let width: CGFloat
    let height: CGFloat

    /// Initialize with a pre-resolved URL (backward compat).
    public init(url: URL?, title: String, icon: String = "book.fill", width: CGFloat = 100, height: CGFloat = 140) {
        self.path = url?.absoluteString
        self.baseURL = ""
        self.title = title
        self.icon = icon
        self.width = width
        self.height = height
    }

    /// Convenience: build URL from an optional path string and a base URL.
    public init(path: String?, title: String, icon: String = "book.fill", width: CGFloat = 100, height: CGFloat = 140, baseURL: String = "") {
        self.title = title
        self.icon = icon
        self.width = width
        self.height = height
        self.baseURL = baseURL
        self.path = path
    }

    public var body: some View {
        if let path, !path.isEmpty {
            CachedAsyncImage(remotePath: path, baseURL: baseURL, width: width, height: height)
        } else {
            PlaceholderThumbnail(title: title, icon: icon, size: CGSize(width: width, height: height))
        }
    }
}
