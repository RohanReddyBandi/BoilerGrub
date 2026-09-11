import Foundation

/// The single seam between the app and Purdue's undocumented menu API.
///
/// Everything above this protocol — views, the plate, the Health service — is
/// written against it and never touches `URLSession`. That is what lets the app
/// run entirely off the saved fixtures in previews and tests, and what will
/// make the inevitable upstream breakage a one-file problem.
protocol MenuProviding: Sendable {
    func menu(for court: DiningCourt, on day: CalendarDay) async throws -> DayMenu
    func itemDetail(id: String) async throws -> ItemDetail
}

/// Failures the UI actually needs to tell apart.
enum MenuServiceError: LocalizedError, Equatable {
    /// The court or item doesn't exist. Upstream signals this with an HTTP 500
    /// and a .NET stack trace rather than a 404, so it is normalised here.
    case notFound
    /// No usable network.
    case offline
    /// Reached the server, but it answered with something unusable.
    case server(statusCode: Int)
    /// The response parsed as JSON but not into anything we recognise — the
    /// most likely shape of a future upstream change.
    case unreadableResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notFound: "That menu isn't available."
        case .offline: "You're offline."
        case .server: "Purdue's menu service is having trouble."
        case .unreadableResponse: "Purdue's menu service returned something unexpected."
        case .transport: "Couldn't reach Purdue's menu service."
        }
    }

    /// What the empty state offers the reader to do about it.
    var recoveryHint: String? {
        switch self {
        case .notFound: "Try another dining court or a different day."
        case .offline: "Menus you've already opened are still available."
        case .server, .unreadableResponse, .transport: "Try again in a moment."
        }
    }

    /// Whether a retry button is worth showing at all.
    var isRetryable: Bool {
        switch self {
        case .notFound: false
        case .offline, .server, .unreadableResponse, .transport: true
        }
    }
}
