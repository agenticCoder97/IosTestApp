import SwiftUI

/// Reusable thumbnail view — tries loading from URL, falls back to a colored placeholder.
public struct StoryThumbnail: View {
    let url: URL?
    let title: String
    let icon: String
    let width: CGFloat
    let height: CGFloat

    /// Initialize with a pre-resolved URL (caller constructs from AppConfig.staticBaseURL + path).
    public init(url: URL?, title: String, icon: String = "book.fill", width: CGFloat = 100, height: CGFloat = 140) {
        self.url = url
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
        if let path, !path.isEmpty {
            if path.hasPrefix("http") {
                self.url = URL(string: path)
            } else {
                self.url = URL(string: baseURL + path)
            }
        } else {
            self.url = nil
        }
    }

    public var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                default:
                    PlaceholderThumbnail(title: title, icon: icon, size: CGSize(width: width, height: height))
                }
            }
        } else {
            PlaceholderThumbnail(title: title, icon: icon, size: CGSize(width: width, height: height))
        }
    }
}
