import SwiftUI
import Core

/// AsyncImage replacement that checks ImageCacheService before fetching from network.
/// Falls back to a placeholder when both cache and network are unavailable.
public struct CachedAsyncImage: View {
    let remotePath: String?
    let baseURL: String
    let width: CGFloat?
    let height: CGFloat?

    @State private var image: UIImage?
    @State private var isLoading = true

    public init(remotePath: String?, baseURL: String, width: CGFloat? = nil, height: CGFloat? = nil) {
        self.remotePath = remotePath
        self.baseURL = baseURL
        self.width = width
        self.height = height
    }

    public var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(AstralColors.surface)
                    .overlay {
                        ProgressView()
                            .tint(AstralColors.muted)
                    }
            } else {
                Rectangle()
                    .fill(AstralColors.surface)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(AstralColors.muted)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: baseURL + (remotePath ?? "")) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        isLoading = true
        guard let path = remotePath, !path.isEmpty else {
            isLoading = false
            return
        }

        if path.hasPrefix("documents:") {
            let root = URL.documentsDirectory.standardizedFileURL
            let file = root.appendingPathComponent(String(path.dropFirst(10))).standardizedFileURL
            if file.path.hasPrefix(root.path + "/") { image = UIImage(contentsOfFile: file.path) }
            isLoading = false
            return
        }
        let urlString = path.hasPrefix("http") || path.hasPrefix("file:") ? path : baseURL + path
        guard let url = URL(string: urlString),
              url.isFileURL || ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            isLoading = false
            return
        }
        if url.isFileURL {
            image = UIImage(contentsOfFile: url.path)
            isLoading = false
            return
        }

        // Scope relative paths to their source so companion changes cannot reuse another cover.
        if let cachedURL = await ImageCacheService.shared.cachedURL(for: urlString),
           let uiImage = UIImage(contentsOfFile: cachedURL.path) {
            guard !Task.isCancelled else { return }
            image = uiImage
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            if let response = response as? HTTPURLResponse,
               (200..<300).contains(response.statusCode),
               let uiImage = UIImage(data: data) {
                _ = try? await ImageCacheService.shared.cache(data: data, for: urlString)
                guard !Task.isCancelled else { return }
                image = uiImage
            }
        } catch {
            // Network failed, no cache — show placeholder
        }
        guard !Task.isCancelled else { return }
        isLoading = false
    }
}
