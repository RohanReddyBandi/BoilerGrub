import Foundation

/// One campus food location.
///
/// This replaces the earlier hardcoded five-court enum. `/locations` returns
/// twelve places across three types, and all twelve serve menus from the same
/// endpoint — so the landing page lists every one of them and the set is no
/// longer something the app can assume.
struct DiningLocation: Codable, Identifiable, Hashable, Sendable {
    /// The API's `LocationId`, e.g. "ERHT". Stable, and used as the cache key.
    let id: String
    /// The display name — **also the menu URL path segment**. For the non-court
    /// locations this contains spaces, apostrophes and exclamation marks
    /// ("Pete's Za at Tarkington Hall") and must be percent-encoded.
    let name: String
    let shortName: String?
    let kind: LocationKind

    /// Service windows with absolute timestamps. The source of truth for
    /// whether a place is open right now.
    let upcomingMeals: [ServiceWindow]
    /// The weekly schedule, used only to answer "when does this open next?"
    /// once `upcomingMeals` has run out.
    let weeklyHours: [WeeklyDay]

    var displayName: String { name }
}

enum LocationKind: String, Codable, CaseIterable, Sendable {
    case diningCourt = "Dining Courts"
    case quickBites = "Quick Bites"
    case onTheGo = "On-the-GO!"
    case other = "Other"

    init(apiValue: String?) {
        self = LocationKind(rawValue: apiValue ?? "") ?? .other
    }

    /// Shown as a stamped label on the location row.
    var label: String {
        switch self {
        case .diningCourt: "dining court"
        case .quickBites: "quick bites"
        case .onTheGo: "on-the-go"
        case .other: "dining"
        }
    }

    /// Dining courts first — they're what most people open the app for.
    var sortOrder: Int {
        switch self {
        case .diningCourt: 0
        case .quickBites: 1
        case .onTheGo: 2
        case .other: 3
        }
    }
}

/// A concrete service window on a specific date.
struct ServiceWindow: Codable, Hashable, Sendable {
    let name: String
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

/// One day of the recurring weekly schedule.
struct WeeklyDay: Codable, Hashable, Sendable {
    /// 0 = Sunday, matching the API's `DayOfWeek`.
    let dayOfWeek: Int
    let meals: [WeeklyMeal]
}

struct WeeklyMeal: Codable, Hashable, Sendable {
    let name: String
    let hours: ServiceHours
}

// MARK: - Open / closed

extension DiningLocation {

    enum OpenState: Equatable, Sendable {
        case open(meal: String, until: Date)
        case closed(next: NextOpening?)

        var isOpen: Bool {
            if case .open = self { return true }
            return false
        }
    }

    struct NextOpening: Equatable, Sendable {
        let meal: String
        let start: Date
    }

    /// Whether this location is serving at `date`.
    ///
    /// `upcomingMeals` is authoritative — its timestamps carry their own
    /// timezone offset, so there is no local-time guesswork. It also contains
    /// windows that have already passed, so "nothing matches" is an ordinary
    /// answer meaning closed, not missing data.
    func openState(at date: Date = Date(), calendar: Calendar = .current) -> OpenState {
        if let current = upcomingMeals.first(where: { $0.contains(date) }) {
            return .open(meal: current.name, until: current.end)
        }
        return .closed(next: nextOpening(after: date, calendar: calendar))
    }

    /// The next time this location serves anything.
    ///
    /// Prefers a concrete upcoming window; falls back to walking the weekly
    /// schedule forward, because `upcomingMeals` is only a handful of entries
    /// long and is frequently exhausted.
    func nextOpening(after date: Date, calendar: Calendar = .current) -> NextOpening? {
        let upcoming = upcomingMeals
            .filter { $0.start > date }
            .min { $0.start < $1.start }
        if let upcoming {
            return NextOpening(meal: upcoming.name, start: upcoming.start)
        }

        guard !weeklyHours.isEmpty else { return nil }
        let byDay = Dictionary(weeklyHours.map { ($0.dayOfWeek, $0) }, uniquingKeysWith: { a, _ in a })

        // Seven days is a full cycle; anything not found in that window means
        // the schedule genuinely never opens.
        for offset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            // The API uses 0 = Sunday; Calendar's `weekday` is 1-based.
            let weekday = calendar.component(.weekday, from: candidateDay) - 1
            guard let day = byDay[weekday] else { continue }

            let starts = day.meals.compactMap { meal -> NextOpening? in
                var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
                components.hour = meal.hours.startHour
                components.minute = meal.hours.startMinute
                guard let start = calendar.date(from: components), start > date else { return nil }
                return NextOpening(meal: meal.name, start: start)
            }

            if let earliest = starts.min(by: { $0.start < $1.start }) { return earliest }
        }
        return nil
    }
}

// MARK: - Fixture naming

/// Turns a location name into a filesystem- and bundle-safe slug.
///
/// Shared by the capture script and `FixtureMenuProvider` so a fixture saved for
/// "Pete's Za at Tarkington Hall" is the one found when that location is asked
/// for. Dining court names are unchanged by this ("Earhart" → "Earhart").
enum FixtureSlug {
    static func make(_ name: String) -> String {
        name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "/", with: "-")
    }
}
