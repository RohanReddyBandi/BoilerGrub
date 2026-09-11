import Foundation

// Wire types, kept deliberately separate from the domain models.
//
// This is an undocumented endpoint that will change without warning, so every
// single field here is optional. Decoding must never throw because the upstream
// dropped a key or changed a type — a missing field degrades one row, it does
// not take down the screen.

struct MenuResponse: Decodable {
    let location: String?
    let date: String?
    let isPublished: Bool?
    let notes: String?
    let meals: [MealResponse]?

    enum CodingKeys: String, CodingKey {
        case location = "Location", date = "Date", isPublished = "IsPublished"
        case notes = "Notes", meals = "Meals"
    }
}

struct MealResponse: Decodable {
    let id: String?
    let name: String?
    let order: Int?
    let status: String?
    let type: String?
    let hours: HoursResponse?
    let notes: String?
    let stations: [StationResponse]?

    enum CodingKeys: String, CodingKey {
        case id = "ID", name = "Name", order = "Order", status = "Status"
        case type = "Type", hours = "Hours", notes = "Notes", stations = "Stations"
    }
}

struct HoursResponse: Decodable {
    let startTime: String?
    let endTime: String?
    enum CodingKeys: String, CodingKey { case startTime = "StartTime", endTime = "EndTime" }
}

struct StationResponse: Decodable {
    let name: String?
    let items: [ItemResponse]?
    enum CodingKeys: String, CodingKey { case name = "Name", items = "Items" }
}

struct ItemResponse: Decodable {
    let id: String?
    let name: String?
    let isVegetarian: Bool?
    let nutritionReady: Bool?
    /// Absent entirely — not empty — on items where `nutritionReady` is false.
    let allergens: [AllergenResponse]?
    let ingredients: String?
    let nutrition: [NutritionResponse]?

    enum CodingKeys: String, CodingKey {
        case id = "ID", name = "Name", isVegetarian = "IsVegetarian"
        case nutritionReady = "NutritionReady", allergens = "Allergens"
        case ingredients = "Ingredients", nutrition = "Nutrition"
    }
}

struct AllergenResponse: Decodable {
    let name: String?
    let value: Bool?
    enum CodingKeys: String, CodingKey { case name = "Name", value = "Value" }
}

struct NutritionResponse: Decodable {
    let name: String?
    let value: Double?
    let labelValue: String?
    let dailyValue: String?
    let ordinal: Int?

    enum CodingKeys: String, CodingKey {
        case name = "Name", value = "Value", labelValue = "LabelValue"
        case dailyValue = "DailyValue", ordinal = "Ordinal"
    }
}

// MARK: - Wire → domain

extension MenuResponse {
    func toDomain(court: DiningCourt, day: CalendarDay) -> DayMenu {
        let meals = (self.meals ?? [])
            .map { $0.toDomain() }
            // Sort by the API's own `order`, never by meal name: the set of
            // names is open-ended (Brunch, Late Lunch) and `Type` mislabels them.
            .sorted { $0.order < $1.order }

        return DayMenu(
            court: court,
            day: day,
            isPublished: isPublished ?? false,
            notes: notes?.nonEmpty,
            meals: meals
        )
    }
}

extension MealResponse {
    func toDomain() -> Meal {
        Meal(
            id: id ?? UUID().uuidString,
            name: name?.nonEmpty ?? "Meal",
            order: order ?? .max,
            status: ServiceStatus(apiValue: status),
            hours: ServiceHours(start: hours?.startTime, end: hours?.endTime),
            notes: notes?.nonEmpty,
            stations: (stations ?? [])
                .map { $0.toDomain() }
                .filter { !$0.items.isEmpty }
        )
    }
}

extension StationResponse {
    func toDomain() -> Station {
        Station(
            name: name?.nonEmpty ?? "Station",
            // An item with no id can't be fetched for nutrition, so it's dropped.
            items: (items ?? []).compactMap { $0.toMenuItem() }
        )
    }
}

extension ItemResponse {
    func toMenuItem() -> MenuItem? {
        guard let id = id?.nonEmpty else { return nil }
        return MenuItem(
            id: id,
            name: name?.nonEmpty ?? "Item",
            isVegetarian: isVegetarian ?? false,
            hasNutrition: nutritionReady ?? false,
            allergens: (allergens ?? []).compactMap { $0.toDomain() }
        )
    }

    func toItemDetail() -> ItemDetail? {
        guard let id = id?.nonEmpty else { return nil }
        return ItemDetail(
            id: id,
            name: name?.nonEmpty ?? "Item",
            isVegetarian: isVegetarian ?? false,
            ingredients: ingredients?.nonEmpty,
            allergens: (allergens ?? []).compactMap { $0.toDomain() },
            facts: NutritionFacts(rows: nutrition ?? [])
        )
    }
}

extension AllergenResponse {
    func toDomain() -> Allergen? {
        guard let name = name?.nonEmpty else { return nil }
        return Allergen(name: name, isPresent: value ?? false)
    }
}

extension NutritionFacts {
    /// Builds facts from the nutrition tape.
    ///
    /// Rows are matched **by name, not by ordinal**. Ordinals were stable across
    /// every sampled item, but positional indexing into an undocumented array is
    /// exactly the kind of assumption that breaks silently and wrongly.
    init?(rows: [NutritionResponse]) {
        guard !rows.isEmpty else { return nil }

        let byName = Dictionary(
            rows.compactMap { row -> (String, NutritionResponse)? in
                guard let name = row.name?.nonEmpty else { return nil }
                return (name, row)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Without calories there is nothing to log to Health, so treat the
        // payload as having no usable nutrition at all.
        guard let calories = byName[NutritionRow.Key.calories]?.value else { return nil }

        self.init(
            servingSize: byName[NutritionRow.Key.servingSize]?.labelValue?.nonEmpty,
            calories: calories,
            proteinGrams: byName[NutritionRow.Key.protein]?.value ?? 0,
            carbGrams: byName[NutritionRow.Key.carbs]?.value ?? 0,
            fatGrams: byName[NutritionRow.Key.fat]?.value ?? 0,
            rows: rows
                .sorted { ($0.ordinal ?? .max) < ($1.ordinal ?? .max) }
                .compactMap { row in
                    guard let name = row.name?.nonEmpty else { return nil }
                    return NutritionRow(
                        name: name,
                        value: row.value,
                        labelValue: row.labelValue?.nonEmpty,
                        dailyValue: row.dailyValue?.nonEmpty
                    )
                }
        )
    }
}

private extension String {
    /// Treats whitespace-only strings as absent, which the API does produce.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
