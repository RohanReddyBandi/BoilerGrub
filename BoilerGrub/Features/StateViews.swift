import SwiftUI

/// Loading looks like a blank ticket coming off the printer: station rules and
/// leader dots in place, values not yet filled in. It occupies roughly the space
/// the real content will, so the screen doesn't jump when it arrives.
struct LoadingTape: View {
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 13) {
                    TickRail()
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle()
                            .fill(Palette.faint)
                            .frame(width: 84, height: 8)
                            .padding(.bottom, 18)
                        ForEach(0..<4, id: \.self) { row in
                            if row > 0 { HairlineRule(color: Palette.faint.opacity(0.35)) }
                            TicketRow {
                                Rectangle()
                                    .fill(Palette.faint)
                                    .frame(width: row.isMultiple(of: 2) ? 150 : 110, height: 11)
                            } trailing: {
                                EmptyView()
                            }
                            .padding(.vertical, 14)
                        }
                    }
                }
            }
        }
        .opacity(dim ? 0.45 : 0.8)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityElement()
        .accessibilityLabel("Loading menu")
    }
}

/// The shared shape of every "nothing here" screen: a stamped label, a line of
/// explanation, and at most one thing to do about it.
struct TicketNotice<Action: View>: View {
    let label: String
    let title: String
    let detail: String?
    @ViewBuilder var action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StampLabel(label, color: Palette.gold)
            Text(title)
                .font(Type.title)
                .foregroundStyle(Palette.bone)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Type.prose)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action.padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 30)
        .accessibilityElement(children: .contain)
    }
}

/// The day exists but the court hasn't posted it. This is a completely normal
/// answer from the API — `IsPublished: false` with an empty meal list — and is
/// deliberately worded so it doesn't read as a failure.
struct NotPostedState: View {
    let day: CalendarDay
    let locationName: String

    var body: some View {
        TicketNotice(
            label: "not posted",
            title: "\(locationName) hasn't posted this day yet.",
            detail: "Menus usually go up a few days ahead. Try a nearer date."
        ) {
            EmptyView()
        }
    }
}

struct NoMealsState: View {
    let locationName: String

    var body: some View {
        TicketNotice(
            label: "no service",
            title: "Nothing is being served at \(locationName) on this day.",
            detail: "It's likely closed all day — try another spot or another date."
        ) {
            EmptyView()
        }
    }
}

/// Two Quick Bites locations — 1bowl and Sushi Boss — publish menus where every
/// row is `NutritionReady: false`. The menu is worth browsing, but nothing in
/// it can be plated, and saying so up front beats letting someone tap a row and
/// find a dead end.
struct NoNutritionNotice: View {
    let locationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StampLabel("menu only", color: Palette.gold, font: Type.micro)
            Text("\(locationName) doesn't publish nutrition, so nothing here can be added to a plate.")
                .font(Type.prose)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Failure states carry the distinction the error type draws: "not found" is a
/// dead end and offers no retry, everything else is probably temporary.
struct FailureState: View {
    let error: MenuServiceError
    let retry: () async -> Void

    var body: some View {
        TicketNotice(
            label: error == .offline ? "offline" : "unavailable",
            title: error.errorDescription ?? "Something went wrong.",
            detail: error.recoveryHint
        ) {
            if error.isRetryable {
                TicketButton(title: "try again") { Task { await retry() } }
            }
        }
    }
}

/// A button as a boxed ticket stub: square corners, gold hairline border, no
/// fill and no shadow.
struct TicketButton: View {
    let title: String
    var emphasised: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StampLabel(title, color: emphasised ? Palette.ground : Palette.gold, font: Type.labelLarge)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(emphasised ? Palette.gold : Color.clear)
                .overlay(Rectangle().stroke(Palette.gold, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
