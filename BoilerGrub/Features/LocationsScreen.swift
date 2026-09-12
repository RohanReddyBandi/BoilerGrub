import SwiftUI

/// The landing page: every campus food location, split by whether it's serving
/// right now.
///
/// Open places come first at full strength; closed ones sit below a tear line,
/// dimmed, with the time they next open. Closed rows stay tappable on purpose —
/// looking up what a hall serves tomorrow is a normal thing to want, and the
/// menu screen has a date control for exactly that.
struct LocationsScreen: View {
    @Environment(AppServices.self) private var services

    @State private var state: LoadState<[DiningLocation]> = .idle
    /// Re-evaluated on a timer so a location flips to "closed" while the app is
    /// open, rather than going stale until the next launch.
    @State private var now = Date()

    let onOpenToday: () -> Void

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LandingHeader(onOpenToday: onOpenToday)

                switch state {
                case .idle, .loading:
                    LoadingTape().padding(.top, 26)
                case .failed(let error):
                    FailureState(error: error) { await load() }
                case .loaded(let locations):
                    LocationList(locations: locations, now: now)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load(force: true) }
        .task { await load() }
        .onReceive(clock) { now = $0 }
    }

    private func load(force: Bool = false) async {
        if force || state.value == nil { state = .loading }
        do {
            state = .loaded(try await services.menu.locations())
            now = Date()
        } catch is CancellationError {
        } catch let error as MenuServiceError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }
}

private struct LandingHeader: View {
    let onOpenToday: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("BoilerGrub")
                .font(Type.display)
                .foregroundStyle(Palette.bone)

            Spacer(minLength: 12)

            Button(action: onOpenToday) {
                StampLabel("today", color: Palette.gold, font: Type.labelLarge)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .overlay(Rectangle().stroke(Palette.goldRule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Today's log")
        }
        .padding(.top, 14)
    }
}

private struct LocationList: View {
    let locations: [DiningLocation]
    let now: Date

    private var open: [DiningLocation] {
        locations.filter { $0.openState(at: now).isOpen }
    }

    private var closed: [DiningLocation] {
        locations.filter { !$0.openState(at: now).isOpen }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if open.isEmpty {
                TicketNotice(
                    label: "all closed",
                    title: "Nothing is serving right now.",
                    detail: "Every dining court and food spot on campus is between meals. They're all still listed below."
                ) { EmptyView() }
            } else {
                LocationGroup(label: "open now", locations: open, now: now, isOpen: true)
            }

            if !closed.isEmpty {
                Perforation().padding(.vertical, open.isEmpty ? 10 : 30)
                LocationGroup(label: "closed", locations: closed, now: now, isOpen: false)
            }
        }
        .padding(.top, 24)
    }
}

private struct LocationGroup: View {
    let label: String
    let locations: [DiningLocation]
    let now: Date
    let isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StampLabel(label, color: isOpen ? Palette.gold : Palette.faint)
                .padding(.bottom, 4)

            ForEach(locations) { location in
                NavigationLink(value: location) {
                    LocationRow(location: location, state: location.openState(at: now))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LocationRow: View {
    let location: DiningLocation
    let state: DiningLocation.OpenState

    private var isOpen: Bool { state.isOpen }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            // The tray rail returns from the menu screen, at full strength for
            // a place that's serving and dimmed for one that isn't. It is the
            // "blocked on or off" signal, not a badge.
            TickRail(emphasised: isOpen)

            VStack(alignment: .leading, spacing: 7) {
                TicketRow {
                    Text(location.displayName)
                        .font(Type.dish)
                        // Closed rows are dimmed, but a location name still has
                        // to be readable — the rail and the chevron carry the
                        // "not serving" signal further down the contrast range.
                        .foregroundStyle(isOpen ? Palette.bone : Palette.muted)
                        .multilineTextAlignment(.leading)
                } trailing: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOpen ? Palette.gold : Palette.faint)
                }

                HStack(spacing: 8) {
                    StampLabel(location.kind.label,
                               color: isOpen ? Palette.muted : Palette.faint,
                               font: Type.micro)
                    Text("·")
                        .font(Type.micro)
                        .foregroundStyle(Palette.faint)
                    StampLabel(statusText,
                               color: isOpen ? Palette.gold : Palette.faint,
                               font: Type.micro)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 15)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(location.displayName), \(location.kind.label), \(statusText)")
    }

    private var statusText: String {
        switch state {
        case .open(let meal, let until):
            "\(meal.lowercased()) until \(until.formatted(date: .omitted, time: .shortened))"
        case .closed(let next):
            next.map { "opens \(relative($0.start))" } ?? "closed"
        }
    }

    /// "opens 5:00 PM" when it's later today, "opens Sat 11:00 AM" otherwise —
    /// a weekday is noise if the answer is a few hours away.
    private func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInTomorrow(date) { return "tomorrow \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

#Preview {
    NavigationStack {
        LocationsScreen(onOpenToday: {})
    }
    .environment(AppServices.preview())
    .environment(Plate())
    .ticketBackground()
}
