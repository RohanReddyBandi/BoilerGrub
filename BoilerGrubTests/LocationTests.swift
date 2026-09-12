import XCTest
@testable import BoilerGrub

/// The landing page sorts every food spot by whether it's serving right now, so
/// the open/closed calculation is the thing most worth pinning down.
final class LocationTests: XCTestCase {

    private let provider = FixtureMenuProvider()

    // MARK: Decoding

    func testDecodesAllTwelveLocations() async throws {
        let locations = try await provider.locations()
        XCTAssertEqual(locations.count, 12)
        XCTAssertEqual(Set(locations.map(\.id)).count, 12, "ids must be unique")
    }

    func testDiningCourtsSortFirst() async throws {
        let kinds = try await provider.locations().map(\.kind)
        let courts = kinds.prefix { $0 == .diningCourt }
        XCTAssertEqual(courts.count, 5, "the five courts lead the list")
        XCTAssertFalse(kinds.dropFirst(5).contains(.diningCourt))
    }

    func testEveryKindIsRecognised() async throws {
        let kinds = Set(try await provider.locations().map(\.kind))
        XCTAssertEqual(kinds, [.diningCourt, .quickBites, .onTheGo],
                       "an unrecognised Type would fall through to .other")
    }

    func testServiceWindowsCarryAbsoluteTimes() async throws {
        let locations = try await provider.locations()
        let withWindows = locations.filter { !$0.upcomingMeals.isEmpty }
        XCTAssertFalse(withWindows.isEmpty)
        for location in withWindows {
            for window in location.upcomingMeals {
                XCTAssertLessThan(window.start, window.end, "\(location.name): \(window.name)")
            }
        }
    }

    func testWeeklyHoursDecode() async throws {
        let locations = try await provider.locations()
        let withSchedule = locations.filter { !$0.weeklyHours.isEmpty }
        XCTAssertFalse(withSchedule.isEmpty, "NormalHours is the fallback for next-opening")
        for location in withSchedule {
            for day in location.weeklyHours {
                XCTAssertTrue((0...6).contains(day.dayOfWeek), "\(location.name) day out of range")
            }
        }
    }

    // MARK: Open / closed

    private func location(
        windows: [ServiceWindow] = [],
        weekly: [WeeklyDay] = []
    ) -> DiningLocation {
        DiningLocation(id: "TEST", name: "Test", shortName: nil, kind: .diningCourt,
                       upcomingMeals: windows, weeklyHours: weekly)
    }

    private func window(_ name: String, from: TimeInterval, to: TimeInterval, base: Date) -> ServiceWindow {
        ServiceWindow(name: name, start: base.addingTimeInterval(from), end: base.addingTimeInterval(to))
    }

    func testOpenWhenNowIsInsideAWindow() {
        let now = Date()
        let place = location(windows: [window("Dinner", from: -3600, to: 3600, base: now)])
        guard case .open(let meal, let until) = place.openState(at: now) else {
            return XCTFail("expected open")
        }
        XCTAssertEqual(meal, "Dinner")
        XCTAssertEqual(until.timeIntervalSince(now), 3600, accuracy: 1)
    }

    /// The API's window list includes meals that have already finished, so
    /// "nothing matches" is an ordinary closed answer, not missing data.
    func testPastWindowsDoNotCountAsOpen() {
        let now = Date()
        let place = location(windows: [window("Lunch", from: -7200, to: -3600, base: now)])
        XCTAssertFalse(place.openState(at: now).isOpen)
    }

    func testWindowEndIsExclusive() {
        let now = Date()
        let place = location(windows: [window("Lunch", from: -3600, to: 0, base: now)])
        XCTAssertFalse(place.openState(at: now).isOpen, "a window ending now is closed")
    }

    func testNextOpeningPrefersTheSoonestFutureWindow() {
        let now = Date()
        let place = location(windows: [
            window("Dinner", from: 7200, to: 10800, base: now),
            window("Lunch", from: 3600, to: 5400, base: now)
        ])
        guard case .closed(let next) = place.openState(at: now) else { return XCTFail("expected closed") }
        XCTAssertEqual(next?.meal, "Lunch", "the earliest upcoming window wins")
    }

    /// `upcomingMeals` runs out often — it's only a handful of entries — so the
    /// weekly schedule has to answer instead.
    func testFallsBackToWeeklyScheduleWhenWindowsAreExhausted() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!

        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 11, hour: 22, minute: 0)))          // Friday night
        let saturday = 6                                                    // 0 = Sunday
        let place = location(
            windows: [],
            weekly: [WeeklyDay(dayOfWeek: saturday, meals: [
                WeeklyMeal(name: "Brunch", hours: try XCTUnwrap(ServiceHours(start: "10:30:00", end: "14:00:00")))
            ])]
        )

        guard case .closed(let next) = place.openState(at: now, calendar: calendar) else {
            return XCTFail("expected closed")
        }
        let opening = try XCTUnwrap(next)
        XCTAssertEqual(opening.meal, "Brunch")
        XCTAssertEqual(calendar.component(.hour, from: opening.start), 10)
        XCTAssertEqual(calendar.component(.minute, from: opening.start), 30)
        XCTAssertTrue(calendar.isDate(opening.start,
                                      inSameDayAs: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))))
    }

    func testNoScheduleMeansNoNextOpening() {
        let place = location()
        guard case .closed(let next) = place.openState(at: Date()) else { return XCTFail("expected closed") }
        XCTAssertNil(next)
    }

    /// A location can legitimately be missing days from its weekly schedule —
    /// 1bowl lists only six — which means closed all day, not bad data.
    func testMissingWeekdaysAreSkipped() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 9)))

        // Only Tuesday (2) is listed.
        let place = location(weekly: [WeeklyDay(dayOfWeek: 2, meals: [
            WeeklyMeal(name: "Lunch", hours: try XCTUnwrap(ServiceHours(start: "11:00:00", end: "14:00:00")))
        ])])

        guard case .closed(let next) = place.openState(at: sunday, calendar: calendar) else {
            return XCTFail("expected closed")
        }
        let opening = try XCTUnwrap(next)
        XCTAssertEqual(calendar.component(.weekday, from: opening.start), 3, "Tuesday")
    }

    // MARK: Fixture slugs

    func testSlugsMatchCapturedFixtureNames() {
        XCTAssertEqual(FixtureSlug.make("Earhart"), "Earhart")
        XCTAssertEqual(FixtureSlug.make("Pete's Za at Tarkington Hall"), "Petes_Za_at_Tarkington_Hall")
        XCTAssertEqual(FixtureSlug.make("Earhart On-the-GO!"), "Earhart_On-the-GO")
        XCTAssertEqual(FixtureSlug.make("1bowl at Meredith Hall"), "1bowl_at_Meredith_Hall")
    }
}
