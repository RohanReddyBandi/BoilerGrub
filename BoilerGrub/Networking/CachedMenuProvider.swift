import Foundation

/// Wraps another provider with an on-disk cache.
///
/// Caching policy follows one fact about the data: **a past day's menu can never
/// change.** So past menus and all item nutrition are kept permanently, and only
/// today's (or a future) menu carries a short expiry, matching the 10 minutes
/// the upstream `Cache-Control` header asks for.
///
/// The read order is: fresh cache → network → *stale* cache. That last step is
/// what makes the app usable on a bad connection or when Purdue's API is down —
/// a menu you've already opened stays openable.
struct CachedMenuProvider: MenuProviding {
    private let upstream: MenuProviding
    private let cache: DiskCache

    /// Matches the upstream `Cache-Control: public, max-age=600`.
    private static let liveMenuTTL: TimeInterval = 600

    init(upstream: MenuProviding, cache: DiskCache = DiskCache()) {
        self.upstream = upstream
        self.cache = cache
    }

    func menu(for court: DiningCourt, on day: CalendarDay) async throws -> DayMenu {
        let key = "menu-\(court.rawValue)-\(day.cacheKey)"
        let ttl: TimeInterval? = day.isPast ? nil : Self.liveMenuTTL

        if let hit = await cache.read(key, as: DayMenu.self, maxAge: ttl) {
            return hit.value
        }

        do {
            let menu = try await upstream.menu(for: court, on: day)
            // Never cache an unpublished day: the court simply hasn't posted it
            // yet, and it will be published later. Caching the empty answer
            // would hide the real menu when it arrives.
            if menu.isPublished {
                await cache.write(menu, key: key)
            }
            return menu
        } catch {
            if let stale = await cache.read(key, as: DayMenu.self, maxAge: nil) {
                return stale.value
            }
            throw error
        }
    }

    func itemDetail(id: String) async throws -> ItemDetail {
        let key = "item-\(id)"

        // An item id always maps to the same nutrition — the court issues a new
        // id when it revises a recipe — so this never needs to expire.
        if let hit = await cache.read(key, as: ItemDetail.self, maxAge: nil) {
            return hit.value
        }

        do {
            let detail = try await upstream.itemDetail(id: id)
            await cache.write(detail, key: key)
            return detail
        } catch {
            throw error
        }
    }
}
