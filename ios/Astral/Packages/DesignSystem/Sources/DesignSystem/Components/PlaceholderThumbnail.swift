import SwiftUI

/// Generates a deterministic colored placeholder thumbnail based on a title string.
/// Used when server thumbnails fail to load or are unavailable.
public struct PlaceholderThumbnail: View {
    let title: String
    let icon: String
    let size: CGSize

    public init(title: String, icon: String = "book.fill", size: CGSize = CGSize(width: 100, height: 140)) {
        self.title = title
        self.icon = icon
        self.size = size
    }

    private var backgroundColor: Color {
        let colors: [Color] = [
            Color(hex: 0x2A2A4A),  // deep indigo
            Color(hex: 0x4A2A2A),  // deep burgundy
            Color(hex: 0x2A4A34),  // deep forest
            Color(hex: 0x40324A),  // deep plum
            Color(hex: 0x324044),  // deep teal
            Color(hex: 0x3A3A2A),  // deep olive
        ]
        let hash = abs(title.hashValue)
        return colors[hash % colors.count]
    }

    private var initial: String {
        String(title.prefix(1)).uppercased()
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)

            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: min(size.width, size.height) * 0.2))
                    .foregroundStyle(.white.opacity(0.3))

                Text(initial)
                    .font(.system(size: min(size.width, size.height) * 0.25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
