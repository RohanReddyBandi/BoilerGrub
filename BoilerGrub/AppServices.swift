import Foundation
import Observation

/// Dependency container. Everything the views need that isn't a view.
///
/// The menu provider is held behind `MenuProviding`, so swapping the live API
/// for bundled fixtures is a one-line change and previews never touch the
/// network.
@Observable
@MainActor
final class AppServices {
    let menu: MenuProviding
    let health: HealthKitService

    /// `health` is built inside the initialiser rather than as a default
    /// argument: default arguments are evaluated in the caller's isolation, and
    /// `HealthKitService` is main-actor bound.
    init(menu: MenuProviding, health: HealthKitService? = nil) {
        self.menu = menu
        self.health = health ?? HealthKitService()
    }

    /// The real thing: live API wrapped in the on-disk cache.
    static func live() -> AppServices {
        AppServices(menu: CachedMenuProvider(upstream: HFSMenuClient()))
    }

    /// Fixture-backed, uncached. Used by every preview in the app.
    static func preview(delay: Duration = .zero, failure: MenuServiceError? = nil) -> AppServices {
        AppServices(menu: FixtureMenuProvider(delay: delay, failure: failure))
    }
}

/// The four states any fetched screen can be in. Having one type for this keeps
/// every screen's empty, loading and failure handling consistent — which matters
/// more than usual here, because an unofficial API means failure is a normal
/// state rather than an exceptional one.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(MenuServiceError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
