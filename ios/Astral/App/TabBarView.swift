import SwiftUI
import DesignSystem

struct TabBarView: View {
    @Binding var activeTab: AppTab
    @Namespace private var tabIndicator

    var body: some View {
        HStack(spacing: 0) {
            tabItem(tab: .comic,  icon: "book.fill",   label: "Comic")
            tabItem(tab: .fanfic, icon: "scroll.fill", label: "Fanfic")
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(AstralColors.surface)
        .clipShape(Capsule())
        .padding(.horizontal, 60)
        .padding(.bottom, 8)
    }

    private func tabItem(tab: AppTab, icon: String, label: String) -> some View {
        let isActive = activeTab == tab
        return Button {
            withAnimation(AstralAnimation.bouncy) {
                activeTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .scaleEffect(isActive ? 1.12 : 1.0)
                    .animation(AstralAnimation.bouncy, value: isActive)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isActive ? AstralColors.gold : AstralColors.muted)
            .animation(AstralAnimation.quick, value: isActive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                if isActive {
                    Capsule()
                        .fill(AstralColors.gold.opacity(0.12))
                        .matchedGeometryEffect(id: "activeTabPill", in: tabIndicator)
                }
            }
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
