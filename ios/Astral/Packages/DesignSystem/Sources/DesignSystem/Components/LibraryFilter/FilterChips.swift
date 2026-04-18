import SwiftUI

/// Single-select (radio-style) chip. Highlighted with gold border when selected.
public struct FilterStatusChip: View {
    public let label: String
    public let isSelected: Bool
    public let action: () -> Void

    public init(_ label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(AstralTypography.caption)
                .foregroundStyle(isSelected ? AstralColors.gold : AstralColors.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AstralColors.gold.opacity(0.15) : AstralColors.elevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AstralColors.gold : AstralColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Multi-select chip (toggle-style). Gold border when active.
public struct FilterToggleChip: View {
    public let label: String
    public let isActive: Bool
    public let action: () -> Void

    public init(_ label: String, isActive: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(AstralTypography.caption)
                .foregroundStyle(isActive ? AstralColors.gold : AstralColors.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? AstralColors.gold.opacity(0.15) : AstralColors.elevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isActive ? AstralColors.gold : AstralColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
