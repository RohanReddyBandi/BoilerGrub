import XCTest
@testable import BoilerGrub

/// These run entirely against the real, unedited API responses captured in
/// `/fixtures`. That's the point of the `MenuProviding` seam: the suite doesn't
/// care whether Purdue's API is up, and it won't start failing in November
/// because a dining court changed its menu.
final class MenuDecodingTests: XCTestCase {

    /// With a test host, `Bundle.main` is the app bundle, which is where the
    /// fixtures are.
    private let provider = FixtureMenuProvider()
    private let captured = CalendarDay(year: 2026, month: 9, day: 11)

    private func allLocations() async throws -> [DiningLocation] {
        try await provider.locations()
    }

    private func courts() async throws -> [DiningLocation] {
        try await allLocations().filter { $0.kind == .diningCourt }
    }

    private func menu(_ location: DiningLocation, _ day: CalendarDay? = nil) async throws -> DayMenu {
        try await provider.menu(for: location, on: day ?? captured)
    }

    /// `XCTUnwrap` takes an autoclosure, which can't carry an `await`, so the
    /// fetch happens first.
    private func named(_ name: String) async throws -> DiningLocation {
        let locations = try await allLocations()
        return try XCTUnwrap(locations.first { $0.name == name })
    }

    // MARK: Decoding

    func testDecodesEveryCapturedLocation() async throws {
        let locations = try await allLocations()
        XCTAssertEqual(locations.count, 12, "/locations returns twelve food spots")

        for location in locations {
            let menu = try await menu(location)
            XCTAssertTrue(menu.isPublished, "\(location.name) fixture should be published")
            XCTAssertFalse(menu.meals.isEmpty, "\(location.name) should decode meals")
            XCTAssertEqual(menu.locationID, location.id)
            XCTAssertEqual(menu.locationName, location.name)
        }
    }

    /// Quick Bites and On-the-GO! names carry spaces, apostrophes and
    /// exclamation marks, and their fixtures are found by slug.
    func testNonCourtLocationsResolveTheirFixtures() async throws {
        for name in ["Pete's Za at Tarkington Hall", "Earhart On-the-GO!", "1bowl at Meredith Hall"] {
            let menu = try await menu(try await named(name))
            XCTAssertFalse(menu.meals.isEmpty, "\(name) should resolve a fixture")
        }
    }

    /// The whole reason `Meal` doesn't use a fixed breakfast/lunch/dinner enum.
    func testOpenEndedMealNamesSurvive() async throws {
        var names = Set<String>()
        for location in try await courts() {
            names.formUnion(try await menu(location).meals.map(\.name))
        }
        XCTAssertTrue(names.contains("Breakfast"))
        XCTAssertTrue(names.contains("Lunch"))
        XCTAssertTrue(names.contains("Dinner"))
        // Hillenbrand serves Brunch; the API types it as "Unknown".
        XCTAssertTrue(names.contains("Brunch"), "Brunch must not be dropped or renamed")
    }

    func testMealsAreSortedByOrderNotByName() async throws {
        for location in try await allLocations() {
            let orders = try await menu(location).meals.map(\.order)
            XCTAssertEqual(orders, orders.sorted(), "\(location.name) meals must be in API order")
        }
    }

    /// `Status: "Closed"` means the location isn't serving that period that day
    /// — it is not a "closed right now" flag. Every closed meal in the fixtures
    /// carries zero stations, which is why the menu screen filters empty meals
    /// out of the selector rather than offering a tab that leads nowhere.
    func testClosedMealsAreEmpty() async throws {
        var sawClosed = false
        for location in try await courts() {
            for meal in try await menu(location).meals where meal.status.isClosed {
                sawClosed = true
                XCTAssertEqual(meal.itemCount, 0, "\(meal.name) is closed but carries items")
            }
        }
        XCTAssertTrue(sawClosed, "fixtures contain closed meals; parsing must surface them")
    }

    func testACourtCanHaveNoServableMeals() async throws {
        let menu = try await menu(try await named("Hillenbrand"))
        let closed = menu.meals.filter { $0.status.isClosed }
        XCTAssertFalse(closed.isEmpty)
        XCTAssertTrue(closed.allSatisfy { $0.stations.isEmpty })
    }

    func testServiceHoursParse() async throws {
        let breakfast = try await menu(try await named("Earhart")).meals.first { $0.name == "Breakfast" }
        let hours = try XCTUnwrap(breakfast?.hours)
        XCTAssertEqual(hours.startHour, 7)
        XCTAssertEqual(hours.startMinute, 0)
        XCTAssertEqual(hours.endHour, 10)
        XCTAssertTrue(hours.contains(hour: 8, minute: 30))
        XCTAssertFalse(hours.contains(hour: 10, minute: 0), "end is exclusive")
        XCTAssertFalse(hours.contains(hour: 6, minute: 59))
    }

    func testMalformedHoursAreNilRatherThanGuessed() {
        XCTAssertNil(ServiceHours(start: nil, end: "10:00:00"))
        XCTAssertNil(ServiceHours(start: "not a time", end: "10:00:00"))
        XCTAssertNil(ServiceHours(start: "99:00:00", end: "10:00:00"))
    }

    /// Placeholder rows ("Deli Bar", "Pizza Toppers") omit the Allergens key
    /// entirely rather than sending an empty array.
    func testPlaceholderItemsDecodeWithoutAllergens() async throws {
        var placeholders: [MenuItem] = []
        for location in try await courts() {
            for meal in try await menu(location).meals {
                for station in meal.stations {
                    placeholders += station.items.filter { !$0.hasNutrition }
                }
            }
        }
        XCTAssertFalse(placeholders.isEmpty, "fixtures contain NutritionReady: false rows")
        for item in placeholders {
            XCTAssertTrue(item.allergens.isEmpty)
            XCTAssertFalse(item.name.isEmpty)
        }
    }

    /// An unpublished future date is a valid 200 response, not an error.
    func testUnpublishedDayIsNotAnError() async throws {
        let day = CalendarDay(year: 2026, month: 12, day: 25)
        let menu = try await provider.menu(for: try await named("Earhart"), on: day)
        XCTAssertFalse(menu.isPublished)
        XCTAssertTrue(menu.meals.isEmpty)
    }

    func testEmptyStationsAreDropped() async throws {
        for location in try await allLocations() {
            for meal in try await menu(location).meals {
                XCTAssertTrue(meal.stations.allSatisfy { !$0.items.isEmpty })
            }
        }
    }

    func testUnknownItemIsNotFound() async {
        do {
            _ = try await provider.itemDetail(id: "00000000-0000-0000-0000-000000000000")
            XCTFail("expected notFound")
        } catch let error as MenuServiceError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: Locations without nutrition

    /// 1bowl and Sushi Boss publish menus where every row is
    /// `NutritionReady: false`, so the menu screen warns up front rather than
    /// offering rows that lead nowhere.
    func testTwoQuickBitesPublishNoNutritionAtAll() async throws {
        for name in ["1bowl at Meredith Hall", "Sushi Boss at South Hall"] {
            let menu = try await menu(try await named(name))
            let plateable = menu.meals.reduce(0) { $0 + $1.plateableItemCount }
            XCTAssertEqual(plateable, 0, "\(name) is expected to publish no nutrition")
            XCTAssertGreaterThan(menu.meals.reduce(0) { $0 + $1.itemCount }, 0,
                                 "\(name) should still list items to browse")
        }
    }

    func testOtherNonCourtLocationsDoHaveNutrition() async throws {
        for name in ["Pete's Za at Tarkington Hall", "Windsor On-the-GO!"] {
            let menu = try await menu(try await named(name))
            let plateable = menu.meals.reduce(0) { $0 + $1.plateableItemCount }
            XCTAssertGreaterThan(plateable, 0, "\(name) should have plateable items")
        }
    }
}
