import XCTest
@testable import BoilerGrub

final class NutritionTests: XCTestCase {

    private let provider = FixtureMenuProvider()
    /// Scrambled Eggs — the item whose real response is checked by hand in NOTES.md.
    private let scrambledEggs = "6c883ba0-e283-4086-ab01-e181a6615435"
    /// "Bread and Condiments" — NutritionReady: false.
    private let placeholder = "86012f74-9046-4051-b1fa-b9b6b8e0e269"

    /// `XCTUnwrap` takes an autoclosure, which can't carry an `await`, so the
    /// fetch and the unwrap are separated here once instead of in every test.
    private func facts(_ id: String) async throws -> NutritionFacts {
        let detail = try await provider.itemDetail(id: id)
        return try XCTUnwrap(detail.facts)
    }

    func testMacrosComeFromTheUnroundedValueField() async throws {
        let facts = try await facts(scrambledEggs)
        // The API's rounded LabelValues are 155 / 11g / 2g / 12g; these are the
        // raw Values behind them.
        XCTAssertEqual(facts.calories, 154.5441, accuracy: 0.0001)
        XCTAssertEqual(facts.proteinGrams, 11.0820, accuracy: 0.0001)
        XCTAssertEqual(facts.carbGrams, 2.2164, accuracy: 0.0001)
        XCTAssertEqual(facts.fatGrams, 12.2104, accuracy: 0.0001)
    }

    /// Serving size is free text with no numeric weight anywhere in the API.
    func testServingSizeIsPreservedVerbatim() async throws {
        let facts = try await facts(scrambledEggs)
        XCTAssertEqual(facts.servingSize, "1/2 Cup")
    }

    func testFullNutritionTapeIsKept() async throws {
        let facts = try await facts(scrambledEggs)
        XCTAssertEqual(facts.rows.count, 14)
        XCTAssertEqual(facts.rows.first?.name, "Serving Size")
        XCTAssertEqual(facts.rows.map(\.name).firstIndex(of: "Protein"), 11)
    }

    /// Every fixture item should agree with Atwater to within a sane margin —
    /// the check that proves `Value` is kcal and grams, not some other unit.
    func testMacroUnitsAgreeWithAtwater() async throws {
        var checked = 0
        for id in provider.fixtureItemIDs {
            guard let facts = try? await provider.itemDetail(id: id).facts, facts.calories > 50 else { continue }
            let estimate = 4 * facts.proteinGrams + 4 * facts.carbGrams + 9 * facts.fatGrams
            XCTAssertEqual(estimate / facts.calories, 1.0, accuracy: 0.3,
                           "Atwater mismatch — units may not be kcal/grams")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 3, "expected several nutrition fixtures")
    }

    func testPlaceholderItemHasNoFacts() async throws {
        let detail = try await provider.itemDetail(id: placeholder)
        XCTAssertNil(detail.facts)
        XCTAssertTrue(detail.allergens.isEmpty)
        XCTAssertNil(detail.ingredients)
        XCTAssertEqual(detail.name, "Bread and Condiments")
    }

    // MARK: Scaling

    func testScalingMultipliesMacros() async throws {
        let facts = try await facts(scrambledEggs)
        let double = facts.scaled(by: 2)
        XCTAssertEqual(double.calories, facts.calories * 2, accuracy: 0.0001)
        XCTAssertEqual(double.proteinGrams, facts.proteinGrams * 2, accuracy: 0.0001)
        XCTAssertEqual(double.carbGrams, facts.carbGrams * 2, accuracy: 0.0001)
        XCTAssertEqual(double.fatGrams, facts.fatGrams * 2, accuracy: 0.0001)
    }

    /// A single serving is exactly what the court published, % daily values
    /// included.
    func testSingleServingPreservesDailyValues() async throws {
        let facts = try await facts(scrambledEggs)
        let same = facts.scaled(by: 1)
        let sodium = try XCTUnwrap(same.rows.first { $0.name == "Sodium" })
        XCTAssertEqual(sodium.dailyValue, "16%")
        XCTAssertEqual(sodium.labelValue, "380mg")
    }

    /// Once the portion changes, a published % daily value is no longer the
    /// published figure.
    func testScalingDropsDailyValues() async throws {
        let facts = try await facts(scrambledEggs)
        let double = facts.scaled(by: 2)
        XCTAssertTrue(double.rows.allSatisfy { $0.dailyValue == nil })
    }

    /// "Calories from fat" has no numeric Value. Leaving its label untouched
    /// beside doubled neighbours would misreport it.
    func testLabelOnlyRowsAreBlankedWhenScaled() async throws {
        let facts = try await facts(scrambledEggs)

        let atOne = try XCTUnwrap(facts.scaled(by: 1).rows.first { $0.name == "Calories from fat" })
        XCTAssertEqual(atOne.labelValue, "108", "unscaled rows pass through intact")

        let atTwo = try XCTUnwrap(facts.scaled(by: 2).rows.first { $0.name == "Calories from fat" })
        XCTAssertNil(atTwo.labelValue, "a stale label must not sit beside scaled values")
        XCTAssertNil(atTwo.displayValue)
    }

    func testScaledRowsCarryTheirUnit() async throws {
        let facts = try await facts(scrambledEggs)
        let sodium = try XCTUnwrap(facts.scaled(by: 2).rows.first { $0.name == "Sodium" })
        XCTAssertEqual(sodium.labelValue, "754mg")
    }

    /// Calcium and Iron have a numeric Value but a null LabelValue.
    func testDisplayValueFallsBackToTheRawNumber() async throws {
        let facts = try await facts(scrambledEggs)
        let calcium = try XCTUnwrap(facts.rows.first { $0.name == "Calcium" })
        XCTAssertNil(calcium.labelValue)
        XCTAssertEqual(calcium.displayValue, "84")
        XCTAssertEqual(calcium.dailyValue, "8%")
    }

    func testAdditionSumsMacros() {
        let a = NutritionFacts(servingSize: "x", calories: 100, proteinGrams: 5,
                               carbGrams: 10, fatGrams: 2, rows: [])
        let b = NutritionFacts(servingSize: "y", calories: 50, proteinGrams: 1,
                               carbGrams: 3, fatGrams: 4, rows: [])
        let sum = a + b
        XCTAssertEqual(sum.calories, 150)
        XCTAssertEqual(sum.proteinGrams, 6)
        XCTAssertEqual(sum.carbGrams, 13)
        XCTAssertEqual(sum.fatGrams, 6)
        XCTAssertNil(sum.servingSize, "a sum of different servings has no single serving size")
    }

    func testNutritionIsNilWithoutCalories() {
        XCTAssertNil(NutritionFacts(rows: []))
        let noCalories = [NutritionResponse(name: "Protein", value: 10, labelValue: "10g",
                                            dailyValue: nil, ordinal: 11)]
        XCTAssertNil(NutritionFacts(rows: noCalories),
                     "without calories there is nothing to log to Health")
    }
}
