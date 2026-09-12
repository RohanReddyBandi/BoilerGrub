import SwiftUI

/// Two families, each with one job.
///
/// - **New York (serif)** carries language: dish names, court names, headings.
///   It is the menu-board voice.
/// - **SF Mono** carries every number in the app, plus small metadata labels.
///   Monospaced digits are what make a column of macros line up like a register
///   tape, and the tape is the whole idea.
///
/// Nothing in the app uses the default UI sans. That is deliberate — it is the
/// single fastest way for an iOS app to look like every other iOS app.
enum Type {

    // MARK: Serif — language

    /// Court name on the picker. The largest type in the app.
    static let display = Font.system(size: 40, weight: .medium, design: .serif)
    /// Screen headings.
    static let title = Font.system(size: 27, weight: .medium, design: .serif)
    /// Dish name in a menu row.
    static let dish = Font.system(size: 18, weight: .regular, design: .serif)
    /// Dish name on the detail screen.
    static let dishLarge = Font.system(size: 31, weight: .medium, design: .serif)
    /// Ingredient prose, notes.
    static let prose = Font.system(size: 14, weight: .regular, design: .serif)

    // MARK: Mono — numbers and metadata

    /// The hero calorie figure. Large enough to be the first thing read, and
    /// set in gold rather than bone — putting Purdue's colour on the single
    /// most important number is what makes the palette read as black-and-gold
    /// rather than black-with-gold-trim.
    static let figureHero = Font.system(size: 72, weight: .light, design: .monospaced)
    /// Plate and daily totals.
    static let figureTotal = Font.system(size: 44, weight: .light, design: .monospaced)
    /// One macro in the three-up macro row.
    static let figureMacro = Font.system(size: 27, weight: .regular, design: .monospaced)
    /// Calories at the right edge of a list row.
    static let figureRow = Font.system(size: 16, weight: .regular, design: .monospaced)
    /// Values in the full nutrition tape.
    static let figureSmall = Font.system(size: 13, weight: .regular, design: .monospaced)

    /// Station names, meal names, field labels. Lowercase by convention —
    /// the brief rules out all-caps eyebrows, and lowercase mono reads as
    /// a stamped ticket rather than a heading.
    static let label = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// Slightly larger label, for tab bars and buttons.
    static let labelLarge = Font.system(size: 13, weight: .medium, design: .monospaced)
    /// Hours, allergen chips, the smallest metadata.
    static let micro = Font.system(size: 10, weight: .regular, design: .monospaced)
}

extension View {
    /// Tracking that makes lowercase mono labels read as stamped, not typed.
    func stamped() -> some View { self.tracking(1.1) }
}
