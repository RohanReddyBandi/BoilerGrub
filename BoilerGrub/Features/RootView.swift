import SwiftUI

struct RootView: View {
    @Environment(Plate.self) private var plate

    @AppStorage("selectedCourt") private var courtRaw = DiningCourt.earhart.rawValue
    @State private var day: CalendarDay = .today
    @State private var showingPlate = false
    @State private var showingToday = false

    private var court: DiningCourt {
        get { DiningCourt(rawValue: courtRaw) ?? .earhart }
        nonmutating set { courtRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            MenuScreen(
                court: Binding(get: { court }, set: { court = $0 }),
                day: $day,
                onOpenToday: { showingToday = true }
            )
            // The tray bar is pinned to the bottom of every menu screen rather
            // than being a tab: the plate is something you accumulate while
            // walking the line, so it belongs underfoot, not in a separate room.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TrayBar(onOpen: { showingPlate = true })
            }
        }
        .sheet(isPresented: $showingPlate) {
            PlateScreen()
        }
        .sheet(isPresented: $showingToday) {
            TodayScreen()
        }
    }
}

#Preview {
    RootView()
        .environment(AppServices.preview())
        .environment(Plate())
        .ticketBackground()
}
