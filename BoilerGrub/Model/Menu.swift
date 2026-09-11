import Foundation

/// One dining court on one calendar day.
struct DayMenu: Codable, Equatable, Sendable {
    let court: DiningCourt
    let day: CalendarDay
    /// False when the court hasn't posted this day yet. This is a *valid*
    /// response, not an error, and gets its own empty state.
    let isPublished: Bool
    let notes: String?
    /// Already sorted by `order`.
    let meals: [Meal]

    var isEmpty: Bool { meals.allSatisfy { $0.stations.isEmpty } }
}

/// A service period. Deliberately **not** a fixed breakfast/lunch/dinner enum:
/// the API also returns "Brunch" and "Late Lunch", and its own `Type` field
/// mislabels those as "Unknown" and "Snack" respectively. The name is treated
/// as free text and ordering comes from `order`.
struct Meal: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let order: Int
    let status: ServiceStatus
    let hours: ServiceHours?
    let notes: String?
    let stations: [Station]

    var itemCount: Int { stations.reduce(0) { $0 + $1.items.count } }
}

enum ServiceStatus: Codable, Equatable, Sendable {
    case open
    case closed
    case other(String)

    init(apiValue: String?) {
        switch apiValue?.lowercased() {
        case "open": self = .open
        case "closed": self = .closed
        case let value?: self = .other(value)
        case nil: self = .other("")
        }
    }

    var isClosed: Bool { self == .closed }
}

/// Service hours, as wall-clock times on the menu's own day.
struct ServiceHours: Codable, Equatable, Sendable {
    let startHour: Int, startMinute: Int
    let endHour: Int, endMinute: Int

    /// Parses the API's `"07:00:00"`. Returns nil for anything unexpected
    /// rather than guessing.
    init?(start: String?, end: String?) {
        guard let s = Self.parse(start), let e = Self.parse(end) else { return nil }
        (startHour, startMinute) = s
        (endHour, endMinute) = e
    }

    private static func parse(_ raw: String?) -> (Int, Int)? {
        guard let parts = raw?.split(separator: ":"), parts.count >= 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// Locale-aware "7:00 AM – 10:00 AM".
    var display: String {
        guard let s = date(startHour, startMinute), let e = date(endHour, endMinute) else { return "" }
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(s.formatted(style)) – \(e.formatted(style))"
    }

    private func date(_ h: Int, _ m: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: h, minute: m))
    }

    /// Whether a given wall-clock time falls inside this window. Used only to
    /// pick which meal to open to; never to gate access to anything.
    func contains(hour: Int, minute: Int) -> Bool {
        let t = hour * 60 + minute
        return t >= startHour * 60 + startMinute && t < endHour * 60 + endMinute
    }
}

/// A serving station within a meal.
struct Station: Codable, Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let items: [MenuItem]
}

/// A menu row. Note this carries *no* nutrition — the menu endpoint doesn't
/// return any. Macros come from `ItemDetail`, fetched per item on tap.
struct MenuItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isVegetarian: Bool
    /// The API's `NutritionReady`. When false this row is a category placeholder
    /// ("Deli Bar", "Pizza Toppers") rather than a dish: there is no nutrition
    /// behind it, so it is not tappable and never worth a network call.
    let hasNutrition: Bool
    let allergens: [Allergen]

    var presentAllergens: [Allergen] { allergens.filter(\.isPresent) }
}

struct Allergen: Codable, Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let isPresent: Bool

    /// "Vegetarian" and "Vegan" arrive inside the allergen array but are dietary
    /// claims, not allergens, and are shown separately.
    var isDietaryClaim: Bool { name == "Vegetarian" || name == "Vegan" }
}

/// A calendar day, independent of time zone drift — the unit the API and the
/// cache are both keyed on.
struct CalendarDay: Hashable, Codable, Sendable, Comparable {
    let year: Int, month: Int, day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    static var today: CalendarDay { CalendarDay(Date()) }

    /// The `MM-DD-YYYY` the endpoint expects.
    var apiPath: String { String(format: "%02d-%02d-%04d", month, day, year) }

    /// Stable, filesystem-safe cache key component.
    var cacheKey: String { String(format: "%04d-%02d-%02d", year, month, day) }

    var date: Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    func adding(days: Int, calendar: Calendar = .current) -> CalendarDay {
        guard let d = date, let moved = calendar.date(byAdding: .day, value: days, to: d) else { return self }
        return CalendarDay(moved, calendar: calendar)
    }

    /// A past day's menu is finished and can never change, which is what makes
    /// permanent caching safe.
    var isPast: Bool { self < .today }
    var isToday: Bool { self == .today }

    static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
