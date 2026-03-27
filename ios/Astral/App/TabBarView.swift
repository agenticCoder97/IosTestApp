import SwiftUI
import DesignSystem

struct TabBarView: View {
    @Binding var activeTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            tabItem(
                tab: .comic,
                icon: "book.fill",
                label: "Comic"
            )

            tabItem(
                tab: .fanfic,
                icon: "scroll.fill",
                label: "Fanfic"
            )
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(AstralColors.surface)
        .clipShape(Capsule())
        .padding(.horizontal, 60)
        .padding(.bottom, 8)
    }

    private func tabItem(tab: AppTab, icon: String, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(activeTab == tab ? AstralColors.gold : AstralColors.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            TabBarView(activeTab: .constant(.comic))
        }
    }
}
