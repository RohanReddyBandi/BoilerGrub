import SwiftUI

struct MenuScreen: View {
    @Binding var court: DiningCourt
    @Binding var day: CalendarDay
    let onOpenToday: () -> Void

    @Environment(AppServices.self) private var services
    @State private var state: LoadState<DayMenu> = .idle
    @State private var selectedMealID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CourtHeader(court: $court, onOpenToday: onOpenToday)
                DayStrip(day: $day)

                Perforation().padding(.vertical, 20)

                switch state {
                case .idle, .loading:
                    LoadingTape()
                case .failed(let error):
                    FailureState(error: error) { await load(force: true) }
                case .loaded(let menu):
                    MenuBody(menu: menu, court: court, selectedMealID: $selectedMealID)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: TaskKey(court: court, day: day)) {
            await load()
        }
    }

    /// Reloads whenever either dimension of the request changes.
    private struct TaskKey: Equatable {
        let court: DiningCourt
        let day: CalendarDay
    }

    private func load(force: Bool = false) async {
        if force { state = .loading } else if state.value == nil { state = .loading }

        do {
            let menu = try await services.menu.menu(for: court, on: day)
            state = .loaded(menu)
            selectedMealID = defaultMeal(in: menu)?.id
        } catch is CancellationError {
            // Superseded by a newer request; leave the screen as it is.
        } catch let error as MenuServiceError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    /// Opens on whichever meal is being served right now, falling back to the
    /// first one with food in it.
    private func defaultMeal(in menu: DayMenu) -> Meal? {
        let servable = menu.meals.filter { !$0.stations.isEmpty }
        guard day.isToday else { return servable.first }

        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let current = servable.first {
            $0.hours?.contains(hour: now.hour ?? 0, minute: now.minute ?? 0) == true
        }
        return current ?? servable.first
    }
}

// MARK: - Header

private struct CourtHeader: View {
    @Binding var court: DiningCourt
    let onOpenToday: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Menu {
                Picker("Dining court", selection: $court) {
                    ForEach(DiningCourt.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(court.displayName)
                        .font(Type.display)
                        .foregroundStyle(Palette.bone)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.gold)
                }
            }
            .accessibilityLabel("Dining court: \(court.displayName). Double tap to change.")

            Spacer(minLength: 12)

            Button(action: onOpenToday) {
                StampLabel("today", color: Palette.gold, font: Type.labelLarge)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .overlay(Rectangle().stroke(Palette.goldRule, lineWidth: 1))
            }
            .accessibilityLabel("Today's log")
        }
        .padding(.top, 14)
    }
}

// MARK: - Body

private struct MenuBody: View {
    let menu: DayMenu
    let court: DiningCourt
    @Binding var selectedMealID: String?

    private var servableMeals: [Meal] {
        menu.meals.filter { !$0.stations.isEmpty }
    }

    private var selectedMeal: Meal? {
        servableMeals.first { $0.id == selectedMealID } ?? servableMeals.first
    }

    var body: some View {
        if !menu.isPublished {
            NotPostedState(day: menu.day, court: court)
        } else if servableMeals.isEmpty {
            NoMealsState(court: court)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                MealSelector(meals: servableMeals, selection: $selectedMealID)

                if let meal = selectedMeal {
                    MealHeading(meal: meal)
                    ForEach(meal.stations) { station in
                        StationBlock(station: station, court: court, mealName: meal.name)
                    }
                }

                if let notes = menu.notes {
                    Text(notes)
                        .font(Type.prose)
                        .foregroundStyle(Palette.faint)
                        .padding(.top, 28)
                }
            }
        }
    }
}

/// Meal names run along a single line, underscored in gold when chosen. Not a
/// segmented control — the set of names is open-ended and a fixed-width control
/// would truncate "Late Lunch" the first time it appeared.
private struct MealSelector: View {
    let meals: [Meal]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(meals) { meal in
                    let isSelected = meal.id == (selection ?? meals.first?.id)
                    Button {
                        selection = meal.id
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            StampLabel(
                                meal.name,
                                color: isSelected ? Palette.gold : Palette.muted,
                                font: Type.labelLarge
                            )
                            Rectangle()
                                .fill(isSelected ? Palette.gold : .clear)
                                .frame(height: 1.5)
                        }
                        .fixedSize()
                    }
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MealHeading: View {
    let meal: Meal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let hours = meal.hours {
                StampLabel(hours.display, color: Palette.muted, font: Type.micro)
            }
            if meal.status.isClosed {
                StampLabel("closed now", color: Palette.faint, font: Type.micro)
            }
            Spacer(minLength: 0)
            StampLabel("\(meal.itemCount) items", color: Palette.faint, font: Type.micro)
        }
        .padding(.top, 18)
        .padding(.bottom, 22)
    }
}

// MARK: - Station

/// A station is introduced by its name and hung off the gold tray rail. The
/// rail is the app's one structural conceit: stacked down the screen, the
/// notches read as stations along a serving line.
private struct StationBlock: View {
    let station: Station
    let court: DiningCourt
    let mealName: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            TickRail()

            VStack(alignment: .leading, spacing: 0) {
                StampLabel(station.name, color: Palette.gold)
                    .padding(.bottom, 12)

                ForEach(Array(station.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        HairlineRule(color: Palette.faint.opacity(0.35))
                    }
                    MenuItemRow(item: item, court: court, mealName: mealName)
                }
            }
        }
        .padding(.bottom, 30)
    }
}

private struct MenuItemRow: View {
    let item: MenuItem
    let court: DiningCourt
    let mealName: String

    @Environment(Plate.self) private var plate

    var body: some View {
        if item.hasNutrition {
            NavigationLink {
                ItemDetailScreen(itemID: item.id, fallbackName: item.name,
                                 court: court, mealName: mealName)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            // A category placeholder — "Deli Bar", "Pizza Toppers". There is no
            // nutrition behind it, so it is shown for completeness but is not a
            // destination and never costs a network call.
            rowContent
        }
    }

    private var rowContent: some View {
        let servings = plate.servings(for: item.id)

        // The vegetarian mark is concatenated into the same Text rather than
        // placed in an HStack beside it: as a sibling view it gets pinned to the
        // first line's trailing edge, which on a wrapped name drops the dot into
        // the middle of the dish ("Yellow Long · Grain Rice").
        return LeaderRow {
            (
                Text(item.name)
                    .font(Type.dish)
                    .foregroundColor(item.hasNutrition ? Palette.bone : Palette.faint)
                + Text(item.isVegetarian ? " ·" : "")
                    .font(Type.dish)
                    .foregroundColor(Palette.gold)
            )
            .multilineTextAlignment(.leading)
        } trailing: {
            if servings > 0 {
                Text("×\(Figure.servings(servings))")
                    .font(Type.figureRow)
                    .foregroundStyle(Palette.gold)
            } else if item.hasNutrition {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            } else {
                StampLabel("no facts", color: Palette.faint, font: Type.micro)
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(servings: servings))
    }

    private func accessibilityLabel(servings: Double) -> String {
        var parts = [item.name]
        if item.isVegetarian { parts.append("vegetarian") }
        if servings > 0 { parts.append("\(Figure.servings(servings)) servings on your plate") }
        if !item.hasNutrition { parts.append("no nutrition information available") }
        return parts.joined(separator: ", ")
    }
}

#Preview("Menu") {
    NavigationStack {
        MenuScreen(court: .constant(.earhart), day: .constant(.today), onOpenToday: {})
    }
    .environment(AppServices.preview())
    .environment(Plate())
    .ticketBackground()
}
