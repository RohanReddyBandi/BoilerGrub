import XCTest
@testable import BoilerGrub

/// Transport-level behaviour, driven through a stubbed `URLProtocol` so no test
/// here touches the network.
///
/// The case that matters most is the 500: Purdue's API answers an unknown
/// location or item id with an HTTP 500 and a .NET stack trace instead of a 404,
/// and the app has to read that as "not found" rather than as an outage.
final class HFSMenuClientTests: XCTestCase {

    private func client(status: Int, body: Data = Data("{}".utf8)) -> HFSMenuClient {
        StubURLProtocol.reset()
        StubURLProtocol.status = status
        StubURLProtocol.body = body

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return HFSMenuClient(session: URLSession(configuration: config))
    }

    private func place(_ name: String, id: String = "TEST") -> DiningLocation {
        DiningLocation(id: id, name: name, shortName: nil, kind: .diningCourt,
                       upcomingMeals: [], weeklyHours: [])
    }

    private func error(from block: () async throws -> Void) async -> MenuServiceError? {
        do { try await block(); return nil } catch let error as MenuServiceError { return error } catch { return nil }
    }

    func testHTTP500IsTreatedAsNotFound() async {
        let client = client(status: 500, body: Data(#"{"Message":"An error has occurred.","ExceptionMessage":"Sequence contains no matching element"}"#.utf8))
        let result = await error { _ = try await client.menu(for: place("Earhart"), on: .today) }
        XCTAssertEqual(result, .notFound, "a 500 from this API means the location doesn't exist")
    }

    func testUnknownItemIDIsAlsoNotFound() async {
        let client = client(status: 500)
        let result = await error { _ = try await client.itemDetail(id: "nope") }
        XCTAssertEqual(result, .notFound)
    }

    func testOtherServerErrorsAreReportedAsServerErrors() async {
        let client = client(status: 503)
        let result = await error { _ = try await client.menu(for: place("Ford"), on: .today) }
        XCTAssertEqual(result, .server(statusCode: 503))
    }

    func testUnparseableBodyIsUnreadableRatherThanACrash() async {
        let client = client(status: 200, body: Data("<html>maintenance</html>".utf8))
        let result = await error { _ = try await client.menu(for: place("Wiley"), on: .today) }
        XCTAssertEqual(result, .unreadableResponse)
    }

    /// A response missing every field must still produce a usable (empty) menu
    /// rather than throwing, because every DTO field is optional by design.
    func testEmptyJSONObjectDegradesToAnEmptyMenu() async throws {
        let client = client(status: 200, body: Data("{}".utf8))
        let menu = try await client.menu(for: place("Windsor", id: "WIND"),
                                         on: CalendarDay(year: 2026, month: 9, day: 11))
        XCTAssertFalse(menu.isPublished)
        XCTAssertTrue(menu.meals.isEmpty)
        XCTAssertEqual(menu.locationID, "WIND")
    }

    func testRequestUsesDisplayNameAndMMDDYYYYPath() async {
        let client = client(status: 200, body: Data("{}".utf8))
        _ = try? await client.menu(for: place("Hillenbrand"), on: CalendarDay(year: 2026, month: 3, day: 4))
        let path = StubURLProtocol.lastRequest?.url?.path ?? ""
        XCTAssertTrue(path.contains("/locations/Hillenbrand/03-04-2026"),
                      "must use the display name and MM-DD-YYYY, got \(path)")
    }

    func testRequestAsksForJSON() async {
        let client = client(status: 200, body: Data("{}".utf8))
        _ = try? await client.menu(for: place("Earhart"), on: .today)
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testUsesHTTPSToAvoidTheUpstreamRedirect() {
        XCTAssertEqual(HFSMenuClient.baseURL.scheme, "https")
    }

    /// Quick Bites and On-the-GO! names carry spaces, apostrophes and
    /// exclamation marks; an unencoded path 500s.
    func testLocationNamesArePercentEncodedInThePath() async {
        let client = client(status: 200, body: Data("{}".utf8))
        _ = try? await client.menu(for: place("Pete's Za at Tarkington Hall"),
                                   on: CalendarDay(year: 2026, month: 9, day: 11))
        let absolute = StubURLProtocol.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(absolute.contains("Pete's%20Za%20at%20Tarkington%20Hall"),
                      "expected an encoded path, got \(absolute)")
    }

    func testLocationsListDecodes() async throws {
        let body = Data(#"{"Types":["Dining Courts"],"Location":[{"LocationId":"ERHT","Name":"Earhart","Type":"Dining Courts","UpcomingMeals":[],"NormalHours":[]}]}"#.utf8)
        let client = client(status: 200, body: body)
        let locations = try await client.locations()
        XCTAssertEqual(locations.map(\.id), ["ERHT"])
        XCTAssertEqual(locations.first?.kind, .diningCourt)
    }

    /// A locations payload with nothing usable in it is a broken response, not
    /// an empty campus.
    func testEmptyLocationsListIsUnreadable() async {
        let client = client(status: 200, body: Data(#"{"Location":[]}"#.utf8))
        let result = await error { _ = try await client.locations() }
        XCTAssertEqual(result, .unreadableResponse)
    }
}

/// Minimal stub transport.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset() {
        status = 200
        body = Data()
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
