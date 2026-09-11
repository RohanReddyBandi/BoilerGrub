import Foundation

/// The five Purdue dining courts.
///
/// `/menus/v2/locations` confirms there are exactly five of type "Dining Courts";
/// everything else it returns is retail or grab-and-go and out of scope. Because
/// the set is small, fixed, and the menu URL needs the *display name* anyway
/// (`Earhart`, not the `ERHT` location id), the app hardcodes them rather than
/// spending a network call at launch to rediscover a constant.
enum DiningCourt: String, CaseIterable, Identifiable, Codable, Sendable {
    case earhart = "Earhart"
    case ford = "Ford"
    case hillenbrand = "Hillenbrand"
    case wiley = "Wiley"
    case windsor = "Windsor"

    var id: String { rawValue }

    /// The path segment used by the menu endpoint.
    var apiName: String { rawValue }

    var displayName: String { rawValue }

    /// The `LocationId` from `/locations`, kept for display as a ticket stamp.
    var code: String {
        switch self {
        case .earhart: "ERHT"
        case .ford: "FORD"
        case .hillenbrand: "HILL"
        case .wiley: "WILY"
        case .windsor: "WIND"
        }
    }
}
