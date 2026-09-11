import XCTest
@testable import BoilerGrub

/// The cache policy exists because of one fact about the data: a past day's
/// menu can never change. These tests pin that policy down, plus the stale
/// fallback that keeps the app usable when Purdue's API is unreachable.
final class CacheTests: XCTestCase {

    private func freshCache() -> DiskCache {
        DiskCache(name: "Tests-\(UUID().uuidString)")
    }

    func testRoundTripsAMenu() async throws {
        let cache = freshCache()
        let menu = try await FixtureMenuProvider().menu(for: .earhart, on: CalendarDay(year: 2026, month: 9, day: 11))

        await cache.write(menu, key: "k")
        let read = await cache.read("k", as: DayMenu.self, maxAge: nil)
        XCTAssertEqual(read?.value, menu)
        await cache.removeAll()
    }

    func testExpiredEntriesAreMisses() async throws {
        let cache = freshCache()
        await cache.write(["a": 1], key: "k")
        // maxAge of 0 makes anything already written count as expired.
        let expired = await cache.read("k", as: [String: Int].self, maxAge: 0)
        XCTAssertNil(expired)
        // ...but it is still there for the stale fallback.
        let stale = await cache.read("k", as: [String: Int].self, maxAge: nil)
        XCTAssertEqual(stale?.value, ["a": 1])
        await cache.removeAll()
    }

    func testUndecodableEntriesAreDiscardedNotThrown() async {
        let cache = freshCache()
        await cache.write(["unexpected": "shape"], key: "k")
        let read = await cache.read("k", as: DayMenu.self, maxAge: nil)
        XCTAssertNil(read, "a shape change must be a miss, never a crash")
        await cache.removeAll()
    }

    func testMissingKeyIsNil() async {
        let cache = freshCache()
        let read = await cache.read("absent", as: DayMenu.self, maxAge: nil)
        XCTAssertNil(read)
    }

    // MARK: Policy

    func testSecondReadOfAPastDayDoesNotHitTheNetwork() async throws {
        let counting = CountingProvider()
        let cache = freshCache()
        let provider = CachedMenuProvider(upstream: counting, cache: cache)
        let past = CalendarDay.today.adding(days: -30)

        _ = try await provider.menu(for: .earhart, on: past)
        _ = try await provider.menu(for: .earhart, on: past)

        let count = await counting.menuCalls
        XCTAssertEqual(count, 1, "a past menu is immutable and should be cached permanently")
        await cache.removeAll()
    }

    func testItemNutritionIsCachedPermanently() async throws {
        let counting = CountingProvider()
        let cache = freshCache()
        let provider = CachedMenuProvider(upstream: counting, cache: cache)

        _ = try await provider.itemDetail(id: "6c883ba0-e283-4086-ab01-e181a6615435")
        _ = try await provider.itemDetail(id: "6c883ba0-e283-4086-ab01-e181a6615435")

        let count = await counting.itemCalls
        XCTAssertEqual(count, 1, "an item id always maps to the same nutrition")
        await cache.removeAll()
    }

    /// The behaviour that keeps an already-opened menu openable on a bad
    /// connection.
    func testStaleCacheIsServedWhenTheNetworkFails() async throws {
        let counting = CountingProvider()
        let cache = freshCache()
        let past = CalendarDay.today.adding(days: -30)

        let working = CachedMenuProvider(upstream: counting, cache: cache)
        let original = try await working.menu(for: .earhart, on: past)

        // Same cache, an upstream that now fails, and an entry forced to expire.
        let failing = CachedMenuProvider(upstream: FixtureMenuProvider(failure: .offline), cache: cache)
        let recovered = try await failing.menu(for: .earhart, on: past)
        XCTAssertEqual(recovered, original)
        await cache.removeAll()
    }

    func testFailureWithNoCacheStillThrows() async {
        let cache = freshCache()
        let provider = CachedMenuProvider(upstream: FixtureMenuProvider(failure: .offline), cache: cache)
        do {
            _ = try await provider.menu(for: .ford, on: CalendarDay(year: 2026, month: 9, day: 11))
            XCTFail("expected offline")
        } catch let error as MenuServiceError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("unexpected: \(error)")
        }
        await cache.removeAll()
    }

    /// An unpublished day will be published later, so caching the empty answer
    /// would hide the real menu when it arrives.
    func testUnpublishedMenusAreNotCached() async throws {
        let counting = CountingProvider()
        let cache = freshCache()
        let provider = CachedMenuProvider(upstream: counting, cache: cache)
        let unpublished = CalendarDay(year: 2026, month: 12, day: 25)

        _ = try await provider.menu(for: .earhart, on: unpublished)
        _ = try await provider.menu(for: .earhart, on: unpublished)

        let count = await counting.menuCalls
        XCTAssertEqual(count, 2, "an unpublished day must be re-checked, not cached")
        await cache.removeAll()
    }
}

/// Counts calls so the cache can be observed from the outside.
private actor CountingProvider: MenuProviding {
    private(set) var menuCalls = 0
    private(set) var itemCalls = 0
    private let inner = FixtureMenuProvider()

    func menu(for court: DiningCourt, on day: CalendarDay) async throws -> DayMenu {
        menuCalls += 1
        return try await inner.menu(for: court, on: day)
    }

    func itemDetail(id: String) async throws -> ItemDetail {
        itemCalls += 1
        return try await inner.itemDetail(id: id)
    }
}
