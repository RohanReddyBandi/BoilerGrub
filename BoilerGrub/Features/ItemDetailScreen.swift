import SwiftUI

/// The nutrition ticket for a single dish.
///
/// This screen exists because the menu endpoint carries no nutrition at all —
/// the macros here come from a second call to `/menus/v2/items/{ID}`, made when
/// the reader taps through. Results are cached permanently, so a dish opened
/// once is instant forever after.
struct ItemDetailScreen: View {
    let itemID: String
    let fallbackName: String
    let court: DiningCourt
    let mealName: String

    @Environment(AppServices.self) private var services
    @Environment(Plate.self) private var plate
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<ItemDetail> = .idle
    @State private var servings: Double = 1
    @State private var showingIngredients = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch state {
                case .idle, .loading:
                    DetailSkeleton(name: fallbackName)
                case .failed(let error):
                    FailureState(error: error) { await load() }
                        .padding(.top, 20)
                case .loaded(let detail):
                    DetailBody(
                        detail: detail,
                        servings: servings,
                        showingIngredients: $showingIngredients
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.ground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StampLabel(mealName, color: Palette.muted)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let detail = state.value, detail.facts != nil {
                AddToPlateBar(
                    servings: $servings,
                    isOnPlate: plate.contains(itemID),
                    onCommit: { commit(detail) },
                    onRemove: {
                        plate.remove(itemID)
                        dismiss()
                    }
                )
            }
        }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            let detail = try await services.menu.itemDetail(id: itemID)
            state = .loaded(detail)
            // Open on whatever is already on the plate, so tapping through from
            // a row you've added shows your real portion, not a fresh serving.
            servings = plate.contains(itemID) ? plate.servings(for: itemID) : 1
        } catch is CancellationError {
        } catch let error as MenuServiceError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    private func commit(_ detail: ItemDetail) {
        if plate.contains(itemID) {
            plate.setServings(servings, for: itemID)
        } else {
            plate.add(detail, court: court, mealName: mealName, servings: servings)
        }
        dismiss()
    }
}

// MARK: - Body

private struct DetailBody: View {
    let detail: ItemDetail
    let servings: Double
    @Binding var showingIngredients: Bool

    /// Everything on this screen reflects the serving count the reader has
    /// dialled in, not a fixed single serving — the number they're looking at
    /// is the number that will land in Health.
    private var scaled: NutritionFacts? {
        detail.facts?.scaled(by: servings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(detail.name)
                .font(Type.dishLarge)
                .foregroundStyle(Palette.bone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            ServingLine(facts: detail.facts, servings: servings)
                .padding(.top, 10)

            if let scaled {
                CalorieFigure(calories: scaled.calories)
                MacroTriad(facts: scaled)
                NutritionTape(rows: scaled.rows)
            } else {
                NoFactsNotice()
            }

            if !detail.presentAllergens.isEmpty {
                AllergenLine(allergens: detail.presentAllergens)
            }

            if let ingredients = detail.ingredients {
                IngredientsBlock(text: ingredients, isExpanded: $showingIngredients)
            }
        }
    }
}

/// The serving line is where the app is honest about the data: the API has no
/// numeric serving weight, only the court's own wording, so that wording is
/// quoted rather than converted into a gram figure nobody measured.
private struct ServingLine: View {
    let facts: NutritionFacts?
    let servings: Double

    var body: some View {
        HStack(spacing: 6) {
            if let serving = facts?.servingSize {
                StampLabel("\(Figure.servings(servings)) × \(serving)", color: Palette.gold)
            } else {
                StampLabel("\(Figure.servings(servings)) × serving", color: Palette.gold)
            }
        }
    }
}

/// The single largest number in the app. Everything else on the screen is
/// arranged around it.
private struct CalorieFigure: View {
    let calories: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DoubleRule().padding(.top, 26)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(Figure.calories(calories))
                    .font(Type.figureHero)
                    .foregroundStyle(Palette.bone)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                StampLabel("calories", color: Palette.muted, font: Type.labelLarge)
                    .padding(.bottom, 12)
            }
            .padding(.top, 16)

            HairlineRule().padding(.top, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Figure.calories(calories)) calories")
    }
}

/// Protein, carbs and fat, given equal weight and divided by hairlines rather
/// than boxed into cards.
private struct MacroTriad: View {
    let facts: NutritionFacts

    var body: some View {
        HStack(spacing: 0) {
            macro("protein", facts.proteinGrams)
            divider
            macro("carbs", facts.carbGrams)
            divider
            macro("fat", facts.fatGrams)
        }
        .padding(.vertical, 22)
        .overlay(alignment: .bottom) { HairlineRule() }
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.goldRule)
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
    }

    private func macro(_ label: String, _ grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(Figure.grams(grams))
                    .font(Type.figureMacro)
                    .foregroundStyle(Palette.bone)
                    .monospacedDigit()
                Text("g")
                    .font(Type.figureSmall)
                    .foregroundStyle(Palette.muted)
            }
            StampLabel(label, color: Palette.muted, font: Type.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Figure.grams(grams)) grams \(label)")
    }
}

/// The remaining ten rows the API returns, printed like a register tape.
private struct NutritionTape: View {
    let rows: [NutritionRow]

    /// The four macros already have the top of the screen to themselves, and
    /// serving size is stated in the header.
    private var secondaryRows: [NutritionRow] {
        let shown = Set([
            NutritionRow.Key.servingSize, NutritionRow.Key.calories,
            NutritionRow.Key.protein, NutritionRow.Key.carbs, NutritionRow.Key.fat
        ])
        return rows.filter { !shown.contains($0.name) }
    }

    var body: some View {
        if !secondaryRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                StampLabel("everything else", color: Palette.muted)
                    .padding(.top, 26)
                    .padding(.bottom, 14)

                ForEach(secondaryRows) { row in
                    LeaderRow {
                        Text(row.name.lowercased())
                            .font(Type.figureSmall)
                            .foregroundStyle(Palette.muted)
                    } trailing: {
                        HStack(spacing: 10) {
                            Text(row.displayValue ?? "—")
                                .font(Type.figureSmall)
                                .foregroundStyle(Palette.bone)
                                .monospacedDigit()
                            if let daily = row.dailyValue {
                                Text(daily)
                                    .font(Type.micro)
                                    .foregroundStyle(Palette.faint)
                                    .monospacedDigit()
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct AllergenLine: View {
    let allergens: [Allergen]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HairlineRule().padding(.top, 24)
            StampLabel("contains", color: Palette.gold).padding(.top, 18)
            Text(allergens.map(\.name).joined(separator: " · "))
                .font(Type.prose)
                .foregroundStyle(Palette.bone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contains \(allergens.map(\.name).joined(separator: ", "))")
    }
}

private struct IngredientsBlock: View {
    let text: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HairlineRule().padding(.top, 24)

            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    StampLabel("ingredients", color: Palette.gold)
                    Spacer()
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.gold)
                }
                .padding(.top, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapses the ingredient list" : "Expands the ingredient list")

            if isExpanded {
                Text(text)
                    .font(Type.prose)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NoFactsNotice: View {
    var body: some View {
        TicketNotice(
            label: "no facts",
            title: "This isn't a dish.",
            detail: "Purdue lists it as a serving station rather than an item, so there's no nutrition behind it."
        ) { EmptyView() }
    }
}

// MARK: - Loading

private struct DetailSkeleton: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(Type.dishLarge)
                .foregroundStyle(Palette.bone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            DoubleRule().padding(.top, 42)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("———")
                    .font(Type.figureHero)
                    .foregroundStyle(Palette.faint)
                StampLabel("calories", color: Palette.faint, font: Type.labelLarge)
                    .padding(.bottom, 12)
            }
            .padding(.top, 16)

            HairlineRule().padding(.top, 6)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading nutrition for \(name)")
    }
}

// MARK: - Add bar

private struct AddToPlateBar: View {
    @Binding var servings: Double
    let isOnPlate: Bool
    let onCommit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Perforation()

            HStack(spacing: 16) {
                ServingStepper(servings: $servings)

                Button(action: onCommit) {
                    StampLabel(isOnPlate ? "update plate" : "add to plate",
                               color: Palette.ground, font: Type.labelLarge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Palette.gold)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if isOnPlate {
                Button(role: .destructive, action: onRemove) {
                    StampLabel("remove from plate", color: Palette.ember, font: Type.micro)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }
        }
        .background(Palette.ground)
    }
}

/// Half-serving steps. A quarter of a "Pizza" or an "8x10 Cut Serving" isn't
/// something anyone can estimate, and the API gives no weight to work from.
struct ServingStepper: View {
    @Binding var servings: Double

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") {
                servings = max(Plate.servingStep, servings - Plate.servingStep)
            }
            .disabled(servings <= Plate.servingStep)

            Text(Figure.servings(servings))
                .font(Type.figureRow)
                .foregroundStyle(Palette.bone)
                .monospacedDigit()
                .frame(minWidth: 34)

            stepButton("plus") {
                servings = min(Plate.maxServings, servings + Plate.servingStep)
            }
            .disabled(servings >= Plate.maxServings)
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().stroke(Palette.goldRule, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Servings")
        .accessibilityValue(Figure.servings(servings))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: servings = min(Plate.maxServings, servings + Plate.servingStep)
            case .decrement: servings = max(Plate.servingStep, servings - Plate.servingStep)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.gold)
                .frame(width: 38, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
