import SwiftUI
import Core
import DesignSystem

struct FanficFilterView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fandom = ""
    @State private var selectedRatings: Set<String> = []
    @State private var selectedStatus: CompletionStatus?
    @State private var wordCountRange: ClosedRange<Double> = 0...500_000
    @State private var language = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Fandom") {
                    TextField("e.g. Harry Potter", text: $fandom)
                }

                Section("Rating") {
                    ForEach(FanficRating.allCases, id: \.self) { rating in
                        Toggle(
                            ratingLabel(rating),
                            isOn: Binding(
                                get: { selectedRatings.contains(rating.rawValue) },
                                set: { isOn in
                                    if isOn {
                                        selectedRatings.insert(rating.rawValue)
                                    } else {
                                        selectedRatings.remove(rating.rawValue)
                                    }
                                }
                            )
                        )
                    }
                }

                Section("Completion Status") {
                    Picker("Status", selection: $selectedStatus) {
                        Text("Any").tag(CompletionStatus?.none)
                        ForEach(CompletionStatus.allCases, id: \.self) { status in
                            Text(status.rawValue.capitalized).tag(Optional(status))
                        }
                    }
                }

                Section("Word Count") {
                    VStack {
                        Text("\(Int(wordCountRange.lowerBound)) – \(Int(wordCountRange.upperBound))")
                            .font(AstralTypography.caption)
                            .foregroundStyle(AstralColors.muted)
                    }
                }

                Section("Language") {
                    TextField("e.g. English", text: $language)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AstralColors.background)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        resetFilters()
                    }
                    .foregroundStyle(AstralColors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        dismiss()
                    }
                    .foregroundStyle(AstralColors.gold)
                }
            }
        }
    }

    private func ratingLabel(_ rating: FanficRating) -> String {
        switch rating {
        case .general: "General Audiences (G)"
        case .teen: "Teen And Up (T)"
        case .mature: "Mature (M)"
        case .explicit: "Explicit (E)"
        }
    }

    private func resetFilters() {
        fandom = ""
        selectedRatings = []
        selectedStatus = nil
        wordCountRange = 0...500_000
        language = ""
    }
}
