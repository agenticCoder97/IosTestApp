import SwiftUI
import Core
import DesignSystem

// MARK: - Filter View (AO3-style)

struct FanficFilterView: View {
    @Bindable var filterState: FanficFilterState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // MARK: Sort
                    FilterSectionCard("Sort") {
                        FlowLayout(spacing: 8) {
                            ForEach(FanficSortOption.allCases, id: \.self) { option in
                                FilterStatusChip(
                                    option.rawValue,
                                    isSelected: filterState.sortBy == option
                                ) {
                                    filterState.sortBy = option
                                }
                            }
                        }
                        FilterSortDirectionToggle(ascending: $filterState.sortAscending)
                    }

                    // MARK: Work Info
                    FilterSectionCard("Work Info") {
                        FilterTextField("Fandom", placeholder: "e.g. Harry Potter", text: $filterState.fandom)

                        Text("Completion Status")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                        FlowLayout(spacing: 8) {
                            FilterStatusChip("All", isSelected: filterState.completionStatus == nil) {
                                filterState.completionStatus = nil
                            }
                            ForEach(CompletionStatus.allCases, id: \.self) { status in
                                FilterStatusChip(
                                    status.rawValue.capitalized,
                                    isSelected: filterState.completionStatus == status.rawValue
                                ) {
                                    filterState.completionStatus = status.rawValue
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            VStack(alignment: .leading) {
                                FilterTextField("Min Words", placeholder: "0", text: Binding(
                                    get: { filterState.wordCountMin.map { String($0) } ?? "" },
                                    set: { filterState.wordCountMin = Int($0) }
                                ))
                            }
                            VStack(alignment: .leading) {
                                FilterTextField("Max Words", placeholder: "any", text: Binding(
                                    get: { filterState.wordCountMax.map { String($0) } ?? "" },
                                    set: { filterState.wordCountMax = Int($0) }
                                ))
                            }
                        }
                    }

                    // MARK: Tags
                    FilterSectionCard("Tags") {
                        Text("Rating")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(FanficRating.allCases, id: \.self) { rating in
                                FilterToggleChip(
                                    ratingLabel(rating),
                                    isActive: filterState.selectedRatings.contains(rating.rawValue)
                                ) {
                                    if filterState.selectedRatings.contains(rating.rawValue) {
                                        filterState.selectedRatings.removeAll { $0 == rating.rawValue }
                                    } else {
                                        filterState.selectedRatings.append(rating.rawValue)
                                    }
                                }
                            }
                        }

                        FilterTextField("Characters", placeholder: "e.g. Hermione", text: $filterState.characters)
                        FilterTextField("Relationship", placeholder: "e.g. Harry/Ginny", text: $filterState.relationship)
                    }

                    // MARK: Source
                    FilterSectionCard("Source") {
                        FlowLayout(spacing: 8) {
                            FilterStatusChip("All", isSelected: filterState.sourceKey == nil) {
                                filterState.sourceKey = nil
                            }
                            ForEach(FanficSource.allCases, id: \.self) { source in
                                FilterStatusChip(
                                    source.rawValue.uppercased(),
                                    isSelected: filterState.sourceKey == source.rawValue
                                ) {
                                    filterState.sourceKey = source.rawValue
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AstralColors.background)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filterState.reset()
                    }
                    .foregroundStyle(AstralColors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AstralColors.gold)
                }
            }
        }
    }

    private func ratingLabel(_ rating: FanficRating) -> String {
        switch rating {
        case .general: "G"
        case .teen: "T"
        case .mature: "M"
        case .explicit: "E"
        }
    }
}
