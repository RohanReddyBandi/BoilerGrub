import XCTest
@testable import BoilerGrub

@MainActor
final class PlateTests: XCTestCase {

    private let provider = FixtureMenuProvider()
    private var earhart: DiningLocation { provider.fixtureLocation(id: "ERHT") }
    private var wiley: DiningLocation { provider.fixtureLocation(id: "WILY") }

    private func detail(_ index: Int = 0) async throws -> ItemDetail {
        let ids = provider.fixtureItemIDs
        for id in ids.dropFirst(index) {
            let detail = try await provider.itemDetail(id: id)
            if detail.facts != nil { return detail }
        }
        throw XCTSkip("no nutrition fixtures available")
    }

    func testAddingAccumulatesTotals() async throws {
        let plate = Plate()
        let a = try await detail(0)
        let b = try await detail(1)

        plate.add(a, location: earhart, mealName: "Lunch")
        plate.add(b, location: earhart, mealName: "Lunch")

        XCTAssertEqual(plate.itemCount, 2)
        let expected = (a.facts?.calories ?? 0) + (b.facts?.calories ?? 0)
        XCTAssertEqual(plate.totals.calories, expected, accuracy: 0.001)
    }

    func testAddingTheSameItemTwiceBumpsServings() async throws {
        let plate = Plate()
        let item = try await detail()
        plate.add(item, location: wiley, mealName: "Dinner")
        plate.add(item, location: wiley, mealName: "Dinner")

        XCTAssertEqual(plate.itemCount, 1, "the same dish should not appear twice")
        XCTAssertEqual(plate.servings(for: item.id), 2)
        XCTAssertEqual(plate.totals.calories, (item.facts?.calories ?? 0) * 2, accuracy: 0.001)
    }

    /// A placeholder row has nothing to total, so it must never reach the plate.
    func testPlaceholderItemsCannotBeAdded() async throws {
        let plate = Plate()
        let placeholder = try await provider.itemDetail(id: "86012f74-9046-4051-b1fa-b9b6b8e0e269")
        plate.add(placeholder, location: provider.fixtureLocation(id: "FORD"), mealName: "Lunch")
        XCTAssertTrue(plate.isEmpty)
    }

    func testServingsStepInHalves() async throws {
        let plate = Plate()
        let item = try await detail()
        plate.add(item, location: provider.fixtureLocation(id: "FORD"), mealName: "Lunch")

        plate.increment(item.id)
        XCTAssertEqual(plate.servings(for: item.id), 1.5)
        plate.decrement(item.id)
        XCTAssertEqual(plate.servings(for: item.id), 1.0)
    }

    /// Stepping down past zero is how an item leaves the plate.
    func testDecrementingToZeroRemovesTheItem() async throws {
        let plate = Plate()
        let item = try await detail()
        plate.add(item, location: provider.fixtureLocation(id: "FORD"), mealName: "Lunch", servings: 0.5)
        plate.decrement(item.id)
        XCTAssertTrue(plate.isEmpty)
    }

    func testServingsAreClamped() async throws {
        let plate = Plate()
        let item = try await detail()
        plate.add(item, location: provider.fixtureLocation(id: "FORD"), mealName: "Lunch")
        plate.setServings(9_000, for: item.id)
        XCTAssertEqual(plate.servings(for: item.id), Plate.maxServings)

        plate.setServings(-5, for: item.id)
        XCTAssertTrue(plate.isEmpty, "a negative count clears the entry rather than going negative")
    }

    func testSnapshotCarriesScaledTotals() async throws {
        let plate = Plate()
        let item = try await detail()
        plate.add(item, location: provider.fixtureLocation(id: "WIND"), mealName: "Dinner", servings: 2)

        let snapshot = plate.snapshot()
        let entry = try XCTUnwrap(snapshot.entries.first)
        XCTAssertEqual(entry.name, item.name)
        XCTAssertEqual(entry.servings, 2)
        XCTAssertEqual(entry.courtName, "Windsor")
        XCTAssertEqual(entry.totals.calories, (item.facts?.calories ?? 0) * 2, accuracy: 0.001)
        XCTAssertEqual(entry.servingSize, item.facts?.servingSize)
    }

    func testClearEmptiesThePlate() async throws {
        let plate = Plate()
        plate.add(try await detail(), location: earhart, mealName: "Lunch")
        plate.clear()
        XCTAssertTrue(plate.isEmpty)
        XCTAssertEqual(plate.totals.calories, 0)
    }
}

final class CalendarDayTests: XCTestCase {

    func testAPIPathIsZeroPaddedMonthDayYear() {
        XCTAssertEqual(CalendarDay(year: 2026, month: 9, day: 11).apiPath, "09-11-2026")
        XCTAssertEqual(CalendarDay(year: 2026, month: 12, day: 5).apiPath, "12-05-2026")
    }

    func testCacheKeySortsChronologically() {
        let a = CalendarDay(year: 2026, month: 9, day: 9).cacheKey
        let b = CalendarDay(year: 2026, month: 9, day: 11).cacheKey
        XCTAssertLessThan(a, b)
    }

    func testOrdering() {
        XCTAssertLessThan(CalendarDay(year: 2025, month: 12, day: 31),
                          CalendarDay(year: 2026, month: 1, day: 1))
        XCTAssertLessThan(CalendarDay(year: 2026, month: 1, day: 1),
                          CalendarDay(year: 2026, month: 2, day: 1))
    }

    func testPastDaysAreEligibleForPermanentCaching() {
        XCTAssertTrue(CalendarDay.today.adding(days: -1).isPast)
        XCTAssertFalse(CalendarDay.today.isPast)
        XCTAssertFalse(CalendarDay.today.adding(days: 1).isPast)
        XCTAssertTrue(CalendarDay.today.isToday)
    }

    func testAddingCrossesMonthBoundaries() {
        let endOfMonth = CalendarDay(year: 2026, month: 1, day: 31)
        XCTAssertEqual(endOfMonth.adding(days: 1), CalendarDay(year: 2026, month: 2, day: 1))
    }
}

final class FigureFormattingTests: XCTestCase {

    func testCaloriesAreWholeNumbers() {
        XCTAssertEqual(Figure.calories(154.5441), "155")
        XCTAssertEqual(Figure.calories(0), "0")
    }

    func testGramsKeepOneDecimalOnlyBelowTen() {
        XCTAssertEqual(Figure.grams(2.2164), "2.2")
        XCTAssertEqual(Figure.grams(12.2104), "12")
    }

    func testServingsDropTrailingZero() {
        XCTAssertEqual(Figure.servings(1), "1")
        XCTAssertEqual(Figure.servings(1.5), "1.5")
        XCTAssertEqual(Figure.servings(2), "2")
    }
}
