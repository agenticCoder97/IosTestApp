import SwiftUI
import Core
import DesignSystem

// MARK: - Filter State (shared between filter view and library)

@Observable
final class FanficFilterState {
    // Work Info
    var fandom: String = ""
    var completionStatus: CompletionStatus? = nil
    var wordCountMin: Int? = nil
    var wordCountMax: Int? = nil

    // Tags
    var selectedRatings: Set<String> = []
    var selectedWarnings: Set<String> = []
    var characters: String = ""
    var relationship: String = ""

    // Sort
    var sortBy: FanficSortOption = .dateAdded
    var sortAscending: Bool = false

    var isActive: Bool {
        !fandom.isEmpty || completionStatus != nil || wordCountMin != nil || wordCountMax != nil ||
        !selectedRatings.isEmpty || !selectedWarnings.isEmpty || !characters.isEmpty || !relationship.isEmpty
    }

    func reset() {
        fandom = ""
        completionStatus = nil
        wordCountMin = nil
        wordCountMax = nil
        selectedRatings = []
        selectedWarnings = []
        characters = ""
        relationship = ""
        sortBy = .dateAdded
        sortAscending = false
    }
}

// MARK: - Sort Option

enum FanficSortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case dateUpdated = "Date Updated"
    case wordCount = "Word Count"
    case title = "Title"
    case chapters = "Chapters"
}

// MARK: - Filter View (AO3-style)

struct FanficFilterView: View {
    @Bindable var filterState: FanficFilterState
    @Environment(\.dismiss) private var dismiss

    private let ratings = [
        ("Not Rated", "NR"),
        ("General Audiences", "G"),
        ("Teen And Up Audiences", "T"),
        ("Mature", "M"),
        ("Explicit", "E"),
    ]

    private let warnings = [
        "Creator Chose Not To Use Archive Warnings",
        "Graphic Depictions Of Violence",
        "Major Character Death",
        "No Archive Warnings Apply",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: Work Info
                    filterSection("Work Info") {
                        filterField("Fandom", text: $filterState.fandom, placeholder: "e.g. Harry Potter")

                        // Completion Status — radio style
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COMPLETION STATUS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AstralColors.muted)
                                .tracking(0.8)

                            HStack(spacing: 8) {
                                statusChip("All", isSelected: filterState.completionStatus == nil) {
                                    filterState.completionStatus = nil
                                }
                                statusChip("Complete", isSelected: filterState.completionStatus == .complete) {
                                    filterState.completionStatus = .complete
                                }
                                statusChip("Ongoing", isSelected: filterState.completionStatus == .ongoing) {
                                    filterState.completionStatus = .ongoing
                                }
                            }
                        }

                        // Word Count range
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WORD COUNT")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AstralColors.muted)
                                .tracking(0.8)

                            HStack(spacing: 8) {
                                wordCountField("Min", value: $filterState.wordCountMin)
                                Text("—").foregroundStyle(AstralColors.muted)
                                wordCountField("Max", value: $filterState.wordCountMax)
                            }
                        }
                    }

                    // MARK: Tags
                    filterSection("Tags") {
                        // Rating
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RATING")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AstralColors.muted)
                                .tracking(0.8)

                            FlowLayout(spacing: 8) {
                                ForEach(ratings, id: \.1) { label, code in
                                    toggleChip(label, isSelected: filterState.selectedRatings.contains(code)) {
                                        if filterState.selectedRatings.contains(code) {
                                            filterState.selectedRatings.remove(code)
                                        } else {
                                            filterState.selectedRatings.insert(code)
                                        }
                                    }
                                }
                            }
                        }

                        // Warnings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WARNINGS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AstralColors.muted)
                                .tracking(0.8)

                            VStack(spacing: 6) {
                                ForEach(warnings, id: \.self) { warning in
                                    warningToggle(warning)
                                }
                            }
                        }

                        filterField("Characters", text: $filterState.characters, placeholder: "e.g. Harry Potter")
                        filterField("Relationship", text: $filterState.relationship, placeholder: "e.g. Draco/Harry")
                    }

                    // MARK: Sort
                    filterSection("Sort") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SORT BY")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AstralColors.muted)
                                .tracking(0.8)

                            FlowLayout(spacing: 8) {
                                ForEach(FanficSortOption.allCases, id: \.self) { option in
                                    toggleChip(option.rawValue, isSelected: filterState.sortBy == option) {
                                        filterState.sortBy = option
                                    }
                                }
                            }
                        }

                        HStack {
                            Text("SORT DIRECTION")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AstralColors.muted)
                                .tracking(0.8)
                            Spacer()
                            Button {
                                filterState.sortAscending.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: filterState.sortAscending ? "arrow.up" : "arrow.down")
                                    Text(filterState.sortAscending ? "Ascending" : "Descending")
                                        .font(AstralTypography.caption)
                                }
                                .foregroundStyle(AstralColors.gold)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer().frame(height: 60)
                }
                .padding(.top, 8)
            }
            .background(AstralColors.background)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        withAnimation { filterState.reset() }
                    }
                    .foregroundStyle(AstralColors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { dismiss() }
                        .foregroundStyle(AstralColors.gold)
                }
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(AstralTypography.bodyMedium)
                    .foregroundStyle(AstralColors.white)
            }
            content()
        }
        .padding(16)
        .background(AstralColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func filterField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AstralColors.muted)
                .tracking(0.8)
            TextField(placeholder, text: text)
                .font(AstralTypography.body)
                .foregroundStyle(AstralColors.white)
                .tint(AstralColors.gold)
                .padding(10)
                .background(AstralColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func wordCountField(_ placeholder: String, value: Binding<Int?>) -> some View {
        TextField(placeholder, text: Binding(
            get: { value.wrappedValue.map { "\($0)" } ?? "" },
            set: { value.wrappedValue = Int($0) }
        ))
        .font(AstralTypography.body)
        .foregroundStyle(AstralColors.white)
        .tint(AstralColors.gold)
        .keyboardType(.numberPad)
        .padding(10)
        .background(AstralColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AstralTypography.caption)
                .foregroundStyle(isSelected ? AstralColors.gold : AstralColors.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AstralColors.gold.opacity(0.2) : AstralColors.elevated)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AstralTypography.caption)
                .foregroundStyle(isSelected ? AstralColors.gold : AstralColors.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? AstralColors.gold.opacity(0.15) : AstralColors.elevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? AstralColors.gold.opacity(0.4) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func warningToggle(_ warning: String) -> some View {
        Button {
            if filterState.selectedWarnings.contains(warning) {
                filterState.selectedWarnings.remove(warning)
            } else {
                filterState.selectedWarnings.insert(warning)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filterState.selectedWarnings.contains(warning) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(filterState.selectedWarnings.contains(warning) ? AstralColors.gold : AstralColors.muted)
                Text(warning)
                    .font(AstralTypography.caption)
                    .foregroundStyle(AstralColors.body)
                    .lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (wrapping chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
