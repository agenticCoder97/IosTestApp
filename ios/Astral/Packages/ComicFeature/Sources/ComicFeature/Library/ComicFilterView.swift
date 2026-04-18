import SwiftUI
import Core
import DesignSystem

struct ComicFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var filterState: ComicFilterState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // MARK: Sort
                    FilterSectionCard("Sort") {
                        FlowLayout(spacing: 8) {
                            ForEach(ComicSortOption.allCases, id: \.self) { option in
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

                    // MARK: Status
                    FilterSectionCard("Status") {
                        FilterToggleChip(
                            "Show Archived",
                            isActive: filterState.showArchived
                        ) {
                            filterState.showArchived.toggle()
                        }

                        Text("Completion")
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
                    }

                    // MARK: Tags
                    FilterSectionCard("Tags") {
                        FilterTextField("Tags contain…", placeholder: "e.g. magic, romance", text: $filterState.tagsKeyword)
                    }

                    // MARK: Category
                    FilterSectionCard("Category") {
                        FilterTextField("Category", placeholder: "e.g. webtoon", text: Binding(
                            get: { filterState.category ?? "" },
                            set: { filterState.category = $0.isEmpty ? nil : $0 }
                        ))
                    }

                    // MARK: Source
                    FilterSectionCard("Source") {
                        FlowLayout(spacing: 8) {
                            FilterStatusChip("All", isSelected: filterState.sourceKey == nil) {
                                filterState.sourceKey = nil
                            }
                            ForEach(ComicSource.allCases, id: \.self) { source in
                                FilterStatusChip(
                                    source.rawValue,
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
            .navigationTitle("Filter")
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
}
