import SwiftUI

/// Black and old gold, and nothing else.
///
/// Every value below is either near-black, Purdue old gold (#CEB888), or gold
/// stepped down in opacity against that black. There is no third hue in the
/// app — no red for destructive actions, no grey that isn't gold-tinted. What
/// used to be a warm bone and an olive-grey secondary are gone; "remove" and
/// "delete" are distinguished by wording and weight rather than by colour.
///
/// The app commits to a single dark surface rather than tracking the system
/// appearance — `UIUserInterfaceStyle = Dark` is pinned in the Info.plist. A
/// menu board doesn't have a light mode.
enum Palette {

    /// Purdue black. A hair off pure #000 so large fields don't smear on OLED.
    static let ground = Color(red: 0.039, green: 0.039, blue: 0.039)

    /// One step up, for the rare recessed strip. Never a card.
    static let groundRaised = Color(red: 0.078, green: 0.075, blue: 0.071)

    /// Purdue old gold, #CEB888. The identity colour, and the colour the most
    /// important figures on any screen are set in.
    static let gold = Color(red: 0.808, green: 0.722, blue: 0.533)

    /// Gold lifted slightly for the hero numerals, so they hold their own at
    /// large sizes against a black field.
    static let goldBright = Color(red: 0.878, green: 0.800, blue: 0.624)

    /// Rules, ticks and hairlines.
    static let goldRule = gold.opacity(0.42)

    /// Primary reading type — dish names and body copy. Near-white with a trace
    /// of the gold's warmth in it so it sits in the same family.
    static let bone = Color(red: 0.949, green: 0.941, blue: 0.925)

    /// Secondary type: stamped labels, station names, metadata. Dimmed gold
    /// rather than a grey, which is what keeps the palette to two colours.
    static let muted = gold.opacity(0.62)

    /// Tertiary: unavailable rows, placeholder items, disabled controls.
    /// Held at 0.45 rather than lower so it still clears a readable contrast
    /// ratio on the black ground — dimming is a signal, not an excuse to make
    /// text unreadable.
    static let faint = gold.opacity(0.45)

    /// The faintest step, for row separators inside a block.
    static let hairline = gold.opacity(0.16)
}
