import Foundation
import SwiftData

/// A plate the reader saved. This is the app's durable record and the source of
/// truth for the daily view.
///
/// It is written **before** the Health sync is attempted, so that a denied
/// permission, an airplane-mode flight, or a device with no Health app never
/// costs the reader their log.
@Model
final class LoggedPlate {
    /// SwiftData gives no ordering guarantee without an explicit sort key.
    var loggedAt: Date = Date()
    var courtName: String = ""
    var mealName: String?

    @Relationship(deleteRule: .cascade, inverse: \LoggedItem.plate)
    var items: [LoggedItem] = []

    /// UUIDs of the HKCorrelations written for this plate, kept so a future
    /// version can reconcile or remove them. Stored as strings because that is
    /// the shape SwiftData handles most predictably.
    var healthSampleIDs: [String] = []

    /// Backing store for `syncState`. Persisted as a raw string rather than an
    /// enum so that adding a case later can't invalidate an existing store.
    var healthSyncRaw: String = HealthSyncState.notSynced.rawValue

    init(loggedAt: Date = Date(), courtName: String, mealName: String? = nil) {
        self.loggedAt = loggedAt
        self.courtName = courtName
        self.mealName = mealName
    }

    var syncState: HealthSyncState {
        get { HealthSyncState(rawValue: healthSyncRaw) ?? .notSynced }
        set { healthSyncRaw = newValue.rawValue }
    }

    // MARK: Totals

    var calories: Double { items.reduce(0) { $0 + $1.totalCalories } }
    var protein: Double { items.reduce(0) { $0 + $1.totalProtein } }
    var carbs: Double { items.reduce(0) { $0 + $1.totalCarbs } }
    var fat: Double { items.reduce(0) { $0 + $1.totalFat } }

    var totals: NutritionFacts {
        NutritionFacts(servingSize: nil, calories: calories, proteinGrams: protein,
                       carbGrams: carbs, fatGrams: fat, rows: [])
    }

    /// Items in the order they were added to the plate.
    var orderedItems: [LoggedItem] {
        items.sorted { $0.position < $1.position }
    }

    /// Rebuilds a snapshot so a failed Health sync can be retried later without
    /// the original plate object still being around.
    func snapshot() -> PlateSnapshot {
        PlateSnapshot(
            loggedAt: loggedAt,
            entries: orderedItems.map {
                PlateSnapshot.Entry(
                    name: $0.name,
                    servings: $0.servings,
                    servingSize: $0.servingSize,
                    courtName: courtName,
                    totals: $0.totals
                )
            }
        )
    }
}

/// One line of a saved plate.
///
/// Per-serving macros are copied in rather than referenced by item id: the
/// upstream API is unofficial and a dish can be revised or vanish outright, and
/// a log of what you ate in March should not be able to change in September.
@Model
final class LoggedItem {
    var itemID: String = ""
    var name: String = ""
    var servings: Double = 1
    /// The court's own free-text serving description, e.g. "1/2 Cup".
    var servingSize: String?
    /// Preserves plate order, which SwiftData relationships don't.
    var position: Int = 0

    var caloriesPerServing: Double = 0
    var proteinPerServing: Double = 0
    var carbsPerServing: Double = 0
    var fatPerServing: Double = 0

    var plate: LoggedPlate?

    init(itemID: String, name: String, servings: Double, servingSize: String?,
         position: Int, perServing: NutritionFacts) {
        self.itemID = itemID
        self.name = name
        self.servings = servings
        self.servingSize = servingSize
        self.position = position
        self.caloriesPerServing = perServing.calories
        self.proteinPerServing = perServing.proteinGrams
        self.carbsPerServing = perServing.carbGrams
        self.fatPerServing = perServing.fatGrams
    }

    var totalCalories: Double { caloriesPerServing * servings }
    var totalProtein: Double { proteinPerServing * servings }
    var totalCarbs: Double { carbsPerServing * servings }
    var totalFat: Double { fatPerServing * servings }

    var totals: NutritionFacts {
        NutritionFacts(servingSize: servingSize, calories: totalCalories,
                       proteinGrams: totalProtein, carbGrams: totalCarbs,
                       fatGrams: totalFat, rows: [])
    }
}

enum HealthSyncState: String, Codable, Sendable {
    /// Saved locally, Health not attempted yet.
    case notSynced
    case synced
    /// Attempted and failed — retryable from the daily view.
    case failed
    /// The reader declined Health access; not an error, and not worth nagging.
    case declined
}
