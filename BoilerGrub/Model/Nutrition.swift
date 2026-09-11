import Foundation

/// Full per-item detail from `/menus/v2/items/{ID}`.
struct ItemDetail: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isVegetarian: Bool
    /// One long comma-separated blob, exactly as the API returns it.
    let ingredients: String?
    let allergens: [Allergen]
    /// Nil when the item is a category placeholder (`NutritionReady == false`).
    let facts: NutritionFacts?

    var presentAllergens: [Allergen] {
        allergens.filter { $0.isPresent && !$0.isDietaryClaim }
    }
}

/// Nutrition for **one serving**, as defined by the dining court.
///
/// Every value is taken from the API's unrounded `Value` field, not the rounded
/// `LabelValue` string, so that multiplying by a serving count doesn't compound
/// rounding error. Units follow what `LabelValue` implies and were verified
/// against an Atwater cross-check — calories in kcal, macros in grams.
struct NutritionFacts: Codable, Equatable, Sendable {
    /// The court's own serving description, verbatim: "1/2 Cup", "Pizza",
    /// "8x10 Cut Serving". There is no numeric serving weight anywhere in the
    /// API, so this can only ever be displayed — never converted to grams.
    let servingSize: String?

    let calories: Double
    let proteinGrams: Double
    let carbGrams: Double
    let fatGrams: Double

    /// The complete nutrition tape in the API's own order, for the detail
    /// screen. Kept whole so the screen can show sodium, fibre, sugar and the
    /// rest without the model having to enumerate every field it might want.
    let rows: [NutritionRow]

    /// Multiplies a single serving by a serving count.
    func scaled(by servings: Double) -> NutritionFacts {
        NutritionFacts(
            servingSize: servingSize,
            calories: calories * servings,
            proteinGrams: proteinGrams * servings,
            carbGrams: carbGrams * servings,
            fatGrams: fatGrams * servings,
            rows: rows.map { $0.scaled(by: servings) }
        )
    }

    static let zero = NutritionFacts(
        servingSize: nil, calories: 0, proteinGrams: 0, carbGrams: 0, fatGrams: 0, rows: []
    )

    static func + (a: NutritionFacts, b: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            servingSize: nil,
            calories: a.calories + b.calories,
            proteinGrams: a.proteinGrams + b.proteinGrams,
            carbGrams: a.carbGrams + b.carbGrams,
            fatGrams: a.fatGrams + b.fatGrams,
            rows: []
        )
    }
}

/// One line of the nutrition tape.
struct NutritionRow: Codable, Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    /// Absent for "Serving Size" and "Calories from fat", which are label-only,
    /// and occasionally absent for "Added Sugar" even though it is numeric.
    let value: Double?
    /// The API's pre-rounded display string, e.g. "12g", "380mg".
    let labelValue: String?
    let dailyValue: String?

    /// The unit suffix, recovered from `labelValue` ("12g" → "g") so that a
    /// scaled value can still be printed with its unit.
    var unit: String {
        guard let labelValue else { return "" }
        let suffix = labelValue.drop { $0.isNumber || $0 == "." || $0 == "," || $0 == "<" || $0 == " " }
        return String(suffix)
    }

    /// What to print in the value column.
    ///
    /// Calcium and Iron come back with a numeric `Value` but a null
    /// `LabelValue`, so falling back to the raw number keeps two real figures on
    /// screen instead of two em dashes. No unit is invented for them — the API
    /// never says what it is, and the % daily value beside it supplies the
    /// context that matters.
    var displayValue: String? {
        if let labelValue { return labelValue }
        guard let value else { return nil }
        return Figure.grams(value)
    }

    func scaled(by servings: Double) -> NutritionRow {
        // A single serving is the figure the API already published, so it is
        // passed through untouched — including its % daily value, which is only
        // meaningful against the serving the label was computed for.
        guard servings != 1 else { return self }

        guard let value else {
            // Label-only rows ("Calories from fat", "Serving Size") carry no
            // number to multiply. Printing the unscaled label next to scaled
            // neighbours would quietly misreport it, so the value is withheld.
            return NutritionRow(name: name, value: nil, labelValue: nil, dailyValue: nil)
        }

        let scaledValue = value * servings
        return NutritionRow(
            name: name,
            value: scaledValue,
            labelValue: Self.format(scaledValue, unit: unit),
            // A percentage of a daily value stops being the published figure
            // once the portion changes, so it is dropped rather than scaled.
            dailyValue: nil
        )
    }

    private static func format(_ value: Double, unit: String) -> String {
        let rounded = value < 10 && value != 0 ? (value * 10).rounded() / 10 : value.rounded()
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return text + unit
    }

    /// The four macros the app treats as primary, keyed by the API's own names.
    enum Key {
        static let servingSize = "Serving Size"
        static let calories = "Calories"
        static let protein = "Protein"
        static let carbs = "Total Carbohydrate"
        static let fat = "Total fat"
    }
}

// MARK: - Number presentation
//
// Macro figures are the most important data on any screen in this app, so their
// formatting is centralised here rather than being improvised per view.

enum Figure {
    /// Calories: always a whole number. "155", "1,240".
    static func calories(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }

    /// Grams: one decimal below 10, whole numbers above. "8.4", "31".
    static func grams(_ value: Double) -> String {
        value < 10
            ? value.formatted(.number.precision(.fractionLength(1)))
            : value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Serving count: "1", "1.5", "2".
    static func servings(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : value.formatted(.number.precision(.fractionLength(1)))
    }
}
