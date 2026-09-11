import Foundation
import OSLog

/// Live client for `api.hfs.purdue.edu`.
///
/// Two endpoints, both undocumented:
///   `GET /menus/v2/locations/{Name}/{MM-DD-YYYY}/`  → a day's menu, no nutrition
///   `GET /menus/v2/items/{ID}`                      → nutrition for one item
struct HFSMenuClient: MenuProviding {
    /// HTTPS directly: the http:// host answers 301 and the extra hop buys
    /// nothing. The path segment is the court's display name ("Earhart"), not
    /// its location id ("ERHT") — sending the id 500s.
    static let baseURL = URL(string: "https://api.hfs.purdue.edu/menus/v2")!

    private let session: URLSession
    private let logger = Logger(subsystem: "com.rohanreddybandi.BoilerGrub", category: "HFS")

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    /// Ephemeral, and explicitly cookie-less: the API hands out an `api_gac`
    /// tracking cookie and a BigIP session cookie on every response, and there
    /// is no reason for a menu reader to carry an identifier around.
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    func menu(for court: DiningCourt, on day: CalendarDay) async throws -> DayMenu {
        let url = Self.baseURL
            .appendingPathComponent("locations")
            .appendingPathComponent(court.apiName)
            .appendingPathComponent(day.apiPath)

        let response: MenuResponse = try await get(url)
        return response.toDomain(court: court, day: day)
    }

    func itemDetail(id: String) async throws -> ItemDetail {
        let url = Self.baseURL.appendingPathComponent("items").appendingPathComponent(id)
        let response: ItemResponse = try await get(url)
        guard let detail = response.toItemDetail() else { throw MenuServiceError.unreadableResponse }
        return detail
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            logger.warning("transport failure for \(url.path, privacy: .public): \(error.code.rawValue)")
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
                throw MenuServiceError.offline
            case .cancelled:
                throw CancellationError()
            default:
                throw MenuServiceError.transport(error.localizedDescription)
            }
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            logger.warning("HTTP \(http.statusCode) for \(url.path, privacy: .public)")
            // An unknown location or item id comes back as a 500 carrying a
            // .NET stack trace, not a 404. For our purposes that is "not found",
            // and it must never surface to the reader as a server outage.
            throw http.statusCode == 500
                ? MenuServiceError.notFound
                : MenuServiceError.server(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("decode failure for \(url.path, privacy: .public): \(error.localizedDescription)")
            throw MenuServiceError.unreadableResponse
        }
    }
}
