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

    private func menu(_ court: DiningCourt, _ day: CalendarDay = CalendarDay(year: 2026, month: 9, day: 11)) async throws -> DayMenu {
        try await provider.menu(for: court, on: day)
    }

    func testDecodesEveryCapturedCourt() async throws {
        for court in DiningCourt.allCases {
            let menu = try await menu(court)
            XCTAssertTrue(menu.isPublished, "\(court.displayName) fixture should be published")
            XCTAssertFalse(menu.meals.isEmpty, "\(court.displayName) should decode meals")
            XCTAssertEqual(menu.court, court)
        }
    }

    /// The whole reason `Meal` doesn't use a fixed breakfast/lunch/dinner enum.
    func testOpenEndedMealNamesSurvive() async throws {
        var names = Set<String>()
        for court in DiningCourt.allCases {
            names.formUnion(try await menu(court).meals.map(\.name))
        }
        XCTAssertTrue(names.contains("Breakfast"))
        XCTAssertTrue(names.contains("Lunch"))
        XCTAssertTrue(names.contains("Dinner"))
        // Hillenbrand serves Brunch; the API types it as "Unknown".
        XCTAssertTrue(names.contains("Brunch"), "Brunch must not be dropped or renamed")
    }

    func testMealsAreSortedByOrderNotByName() async throws {
        for court in DiningCourt.allCases {
            let orders = try await menu(court).meals.map(\.order)
            XCTAssertEqual(orders, orders.sorted(), "\(court.displayName) meals must be in API order")
        }
    }

    /// `Status: "Closed"` means the court isn't serving that period at all that
    /// day — it is not a "closed right now" flag. Every closed meal in the
    /// fixtures carries zero stations, which is why the menu screen filters
    /// empty meals out of the selector rather than offering a tab that leads
    /// nowhere.
    func testClosedMealsAreEmpty() async throws {
        var sawClosed = false
        for court in DiningCourt.allCases {
            for meal in try await menu(court).meals where meal.status.isClosed {
                sawClosed = true
                XCTAssertEqual(meal.itemCount, 0, "\(meal.name) is closed but carries items")
            }
        }
        XCTAssertTrue(sawClosed, "fixtures contain closed meals; parsing must surface them")
    }

    /// Hillenbrand has Brunch, Lunch and Late Lunch all closed on the captured
    /// day, so a court can legitimately have nothing browsable.
    func testACourtCanHaveNoServableMeals() async throws {
        let menu = try await menu(.hillenbrand)
        let closed = menu.meals.filter { $0.status.isClosed }
        XCTAssertFalse(closed.isEmpty)
        XCTAssertTrue(closed.allSatisfy { $0.stations.isEmpty })
    }

    func testServiceHoursParse() async throws {
        let breakfast = try await menu(.earhart).meals.first { $0.name == "Breakfast" }
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
        for court in DiningCourt.allCases {
            for meal in try await menu(court).meals {
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
        let menu = try await provider.menu(for: .earhart, on: day)
        XCTAssertFalse(menu.isPublished)
        XCTAssertTrue(menu.meals.isEmpty)
    }

    func testEmptyStationsAreDropped() async throws {
        for court in DiningCourt.allCases {
            for meal in try await menu(court).meals {
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
}
