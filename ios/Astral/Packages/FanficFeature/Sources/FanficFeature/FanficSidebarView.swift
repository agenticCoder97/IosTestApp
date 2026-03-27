import SwiftUI
import DesignSystem

struct FanficSidebarView: View {
    @Binding var isOpen: Bool
    @Binding var activeSection: FanficSection

    private let sidebarWidth: CGFloat = 260

    var body: some View {
        ZStack(alignment: .trailing) {
            if isOpen {
                AstralColors.background.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            isOpen = false
                        }
                    }
            }

            HStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fanfic")
                        .font(AstralTypography.title)
                        .foregroundStyle(AstralColors.white)
                        .padding(.bottom, 16)

                    ForEach(FanficSection.allCases, id: \.self) { section in
                        sidebarRow(section)
                    }

                    Spacer()
                }
                .padding(24)
                .frame(width: sidebarWidth)
                .background(AstralColors.surface)
            }
            .offset(x: isOpen ? 0 : sidebarWidth)
        }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: isOpen)
    }

    private func sidebarRow(_ section: FanficSection) -> some View {
        Button {
            activeSection = section
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                isOpen = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .frame(width: 24)
                Text(section.rawValue)
                    .font(AstralTypography.body)
                Spacer()
            }
            .foregroundStyle(activeSection == section ? AstralColors.gold : AstralColors.body)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                activeSection == section
                    ? AstralColors.gold.opacity(0.1)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
