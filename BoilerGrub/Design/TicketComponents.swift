import SwiftUI

// MARK: - Rules and tear lines
//
// The app has no cards and no shadows. Every separation in the interface is
// done with a line: a hairline rule for a minor break, a perforation for a
// section break, a double rule for a total. This is the entire vocabulary.

/// A single gold hairline. The workhorse divider.
struct HairlineRule: View {
    var color: Color = Palette.goldRule
    var weight: CGFloat = 0.5
    var body: some View {
        Rectangle().fill(color).frame(height: weight)
    }
}

/// The double rule that sits above a total, borrowed straight from a register
/// tape. Its only job is to say "everything below this line is the sum."
struct DoubleRule: View {
    var body: some View {
        VStack(spacing: 2.5) {
            HairlineRule(color: Palette.gold, weight: 1)
            HairlineRule(color: Palette.gold, weight: 1)
        }
    }
}

/// A tear-off perforation: the dashed line you'd rip a meal ticket along.
/// Used between major sections — meals, and the head and body of the plate.
struct Perforation: View {
    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(Palette.goldRule),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1.5, 5])
            )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - The tray rail
//
// The one bold structural idea: a gold spine running down the leading edge of
// the content, notched with a tick at every station. It reads as the rail of a
// cafeteria tray line, and it is what makes the app recognisable at a glance.
// It is also purely decorative, so it is hidden from assistive technology.

/// A vertical gold hairline with a single horizontal notch at the top, marking
/// where one station begins. Stack these and the notches become a tray line.
struct TickRail: View {
    /// Drawn at full strength for the meal currently being served.
    var emphasised: Bool = false

    var body: some View {
        Canvas { context, size in
            let x: CGFloat = 0.5
            let strength = emphasised ? Palette.gold : Palette.goldRule

            var spine = Path()
            spine.move(to: CGPoint(x: x, y: 0))
            spine.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(spine, with: .color(strength), style: StrokeStyle(lineWidth: 1))

            var notch = Path()
            notch.move(to: CGPoint(x: x, y: 0.5))
            notch.addLine(to: CGPoint(x: size.width, y: 0.5))
            context.stroke(notch, with: .color(strength), style: StrokeStyle(lineWidth: 1))
        }
        .frame(width: 9)
        .accessibilityHidden(true)
    }
}

// MARK: - Labels

/// A lowercase, letter-spaced mono label. Deliberately *not* all-caps: the
/// stamped lowercase reads as ticket furniture instead of a heading.
struct StampLabel: View {
    let text: String
    var color: Color = Palette.muted
    var font: Font = Type.label

    init(_ text: String, color: Color = Palette.muted, font: Font = Type.label) {
        self.text = text
        self.color = color
        self.font = font
    }

    var body: some View {
        Text(text.lowercased())
            .font(font)
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

// MARK: - Leader row

/// A name on the left, a figure on the right, and a run of dots between them —
/// the way a printed menu or a receipt connects an item to its price. The dots
/// are what stop the eye from losing the line on a wide phone.
struct LeaderRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            leading
            LeaderDots()
            trailing
        }
    }
}

/// The run of dots itself. Expands to fill whatever space is left over.
struct LeaderDots: View {
    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(Palette.faint),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.5, 4])
            )
        }
        .frame(height: 4)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Screen chrome

/// Every screen sits on the same ground colour, edge to edge.
struct TicketBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Palette.ground.ignoresSafeArea())
            .tint(Palette.gold)
    }
}

extension View {
    func ticketBackground() -> some View { modifier(TicketBackground()) }
}

// MARK: - Sheet header

/// The sheets carry their own header rather than a navigation bar.
///
/// On iOS 26 a `ToolbarItem` button is given a filled, rounded capsule by
/// default — which is precisely the identical-rounded-shape look this design
/// avoids, and it can't be fully stripped from inside a toolbar. Building the
/// header out of the same rules and stamps as the rest of the app keeps one
/// vocabulary on screen and removes the navigation bar's dead space.
struct SheetHeader<Trailing: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Button(action: onClose) {
                    StampLabel("close", color: Palette.muted, font: Type.micro)
                        .padding(.trailing, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
                StampLabel(title, color: Palette.gold, font: Type.labelLarge)
                Spacer()

                trailing
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            HairlineRule()
        }
        .background(Palette.ground)
    }
}
