import Foundation

/// Serves the real, unedited API responses captured in `/fixtures` and bundled
/// into the app.
///
/// This is what the brief's "runs off the saved fixtures in tests and previews"
/// means in practice: no previews hitting the network, no tests that fail when
/// Purdue's API is down or when a dining court changes its menu.
struct FixtureMenuProvider: MenuProviding {
    /// Simulated latency, so previews and tests can exercise loading states.
    var delay: Duration = .zero
    /// Forces every call to fail, for exercising error states in previews.
    var failure: MenuServiceError?
    var bundle: Bundle = .main

    init(delay: Duration = .zero, failure: MenuServiceError? = nil, bundle: Bundle = .main) {
        self.delay = delay
        self.failure = failure
        self.bundle = bundle
    }

    func menu(for court: DiningCourt, on day: CalendarDay) async throws -> DayMenu {
        try await pause()
        if let failure { throw failure }

        // Prefer an exact date match, then fall back to whichever day was
        // captured for that court — a preview asking for "today" should still
        // get a real menu rather than an empty state.
        let exact = "menu-\(court.apiName)-\(day.apiPath)"
        let data = try loadJSON(named: exact)
            ?? loadJSON(matchingPrefix: "menu-\(court.apiName)-")
            ?? { throw MenuServiceError.notFound }()

        guard let response = try? JSONDecoder().decode(MenuResponse.self, from: data) else {
            throw MenuServiceError.unreadableResponse
        }
        return response.toDomain(court: court, day: day)
    }

    func itemDetail(id: String) async throws -> ItemDetail {
        try await pause()
        if let failure { throw failure }

        guard let data = try loadJSON(named: "item-\(id)") else { throw MenuServiceError.notFound }
        guard let response = try? JSONDecoder().decode(ItemResponse.self, from: data),
              let detail = response.toItemDetail() else {
            throw MenuServiceError.unreadableResponse
        }
        return detail
    }

    // MARK: - Loading

    private func pause() async throws {
        guard delay > .zero else { return }
        try await Task.sleep(for: delay)
    }

    private func loadJSON(named name: String) throws -> Data? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        return try Data(contentsOf: url)
    }

    private func loadJSON(matchingPrefix prefix: String) throws -> Data? {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else { return nil }
        guard let match = urls
            .filter({ $0.lastPathComponent.hasPrefix(prefix) })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .first
        else { return nil }
        return try Data(contentsOf: match)
    }

    /// Every item id that has a bundled nutrition fixture. Used by previews to
    /// pick an item that will actually resolve.
    var fixtureItemIDs: [String] {
        (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("item-") }
            .map { $0.replacingOccurrences(of: "item-", with: "")
                     .replacingOccurrences(of: ".json", with: "") }
            .sorted()
    }
}
