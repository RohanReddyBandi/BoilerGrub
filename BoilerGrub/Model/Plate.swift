import Foundation
import Observation

/// The plate being built right now.
///
/// Held in memory rather than SwiftData: a plate under construction is a
/// scratch surface, and only becomes a durable record once the reader saves it.
/// Every entry carries the item's full `ItemDetail`, which means the running
/// totals never need another network call as servings change.
@Observable
@MainActor
final class Plate {

    struct Entry: Identifiable, Equatable {
        let detail: ItemDetail
        let courtName: String
        let mealName: String?
        var servings: Double

        var id: String { detail.id }
        var perServing: NutritionFacts { detail.facts ?? .zero }
        /// Per-serving nutrition multiplied by the serving count.
        var totals: NutritionFacts { perServing.scaled(by: servings) }
    }

    private(set) var entries: [Entry] = []

    /// Serving counts move in half-servings: a quarter of a "Pizza" is not a
    /// thing anyone can estimate, and the API gives no weight to work from.
    static let servingStep = 0.5
    static let maxServings = 12.0

    var isEmpty: Bool { entries.isEmpty }
    var itemCount: Int { entries.count }

    /// The running total across every entry.
    var totals: NutritionFacts {
        entries.reduce(NutritionFacts.zero) { $0 + $1.totals }
    }

    func contains(_ itemID: String) -> Bool {
        entries.contains { $0.id == itemID }
    }

    func servings(for itemID: String) -> Double {
        entries.first { $0.id == itemID }?.servings ?? 0
    }

    /// Adds an item, or bumps an existing entry by one serving.
    func add(_ detail: ItemDetail, court: DiningCourt, mealName: String?, servings: Double = 1) {
        guard detail.facts != nil else { return }   // placeholder rows have nothing to total

        if let index = entries.firstIndex(where: { $0.id == detail.id }) {
            entries[index].servings = min(entries[index].servings + servings, Self.maxServings)
        } else {
            entries.append(
                Entry(detail: detail,
                      courtName: court.displayName,
                      mealName: mealName,
                      servings: min(servings, Self.maxServings))
            )
        }
    }

    func setServings(_ value: Double, for itemID: String) {
        guard let index = entries.firstIndex(where: { $0.id == itemID }) else { return }
        let clamped = min(max(value, 0), Self.maxServings)
        if clamped <= 0 {
            entries.remove(at: index)
        } else {
            entries[index].servings = clamped
        }
    }

    func increment(_ itemID: String) {
        setServings(servings(for: itemID) + Self.servingStep, for: itemID)
    }

    func decrement(_ itemID: String) {
        setServings(servings(for: itemID) - Self.servingStep, for: itemID)
    }

    func remove(_ itemID: String) {
        entries.removeAll { $0.id == itemID }
    }

    func clear() {
        entries.removeAll()
    }

    /// A value snapshot for handing to the Health service and SwiftData.
    func snapshot(at date: Date = Date()) -> PlateSnapshot {
        PlateSnapshot(
            loggedAt: date,
            entries: entries.map {
                PlateSnapshot.Entry(
                    name: $0.detail.name,
                    servings: $0.servings,
                    servingSize: $0.perServing.servingSize,
                    courtName: $0.courtName,
                    totals: $0.totals
                )
            }
        )
    }
}
