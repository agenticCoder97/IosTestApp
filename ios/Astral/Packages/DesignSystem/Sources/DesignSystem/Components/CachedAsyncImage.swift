import SwiftUI
import Core

/// AsyncImage replacement that checks ImageCacheService before fetching from network.
/// Falls back to a placeholder when both cache and network are unavailable.
public struct CachedAsyncImage: View {
    let remotePath: String?
    let baseURL: String
    let width: CGFloat
    let height: CGFloat

    @State private var image: UIImage?
    @State private var isLoading = true

    public init(remotePath: String?, baseURL: String, width: CGFloat, height: CGFloat) {
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
        .task(id: remotePath) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let path = remotePath, !path.isEmpty else {
            isLoading = false
            return
        }

        // 1. Check disk cache
        if let cachedURL = await ImageCacheService.shared.cachedURL(for: path),
           let uiImage = UIImage(contentsOfFile: cachedURL.path) {
            image = uiImage
            isLoading = false
            return
        }

        // 2. Fetch from network
        let urlString = path.hasPrefix("http") ? path : baseURL + path
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                _ = try? await ImageCacheService.shared.cache(data: data, for: path)
                image = uiImage
            }
        } catch {
            // Network failed, no cache — show placeholder
        }
        isLoading = false
    }
}
