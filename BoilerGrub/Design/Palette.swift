import SwiftUI

/// The app commits to a single dark "menu board" surface rather than tracking
/// the system appearance. A chalkboard is not a thing that has a light mode.
/// `UIUserInterfaceStyle = Dark` is pinned in the Info.plist to match.
enum Palette {
    /// Purdue black, warmed very slightly so it doesn't read as pure #000 on OLED.
    static let ground = Color(red: 0.055, green: 0.055, blue: 0.051)

    /// One step up from the ground, for the rare recessed area. Not a card.
    static let groundRaised = Color(red: 0.094, green: 0.094, blue: 0.086)

    /// Purdue old gold, #CEB888.
    static let gold = Color(red: 0.808, green: 0.722, blue: 0.533)

    /// Gold at rest — rules and ticks, present but not shouting.
    static let goldRule = Color(red: 0.808, green: 0.722, blue: 0.533).opacity(0.45)

    /// Primary type. Bone rather than white; white on black is glaring.
    static let bone = Color(red: 0.929, green: 0.918, blue: 0.878)

    /// Secondary type — station names, serving labels, metadata.
    static let muted = Color(red: 0.561, green: 0.545, blue: 0.482)

    /// Tertiary — closed meals, disabled rows, leader dots.
    static let faint = Color(red: 0.345, green: 0.337, blue: 0.306)

    /// The only non-Purdue hue in the app, reserved exclusively for destructive
    /// actions so that "remove" never has to borrow gold's authority.
    static let ember = Color(red: 0.776, green: 0.376, blue: 0.263)
}
