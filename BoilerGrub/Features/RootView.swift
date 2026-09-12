import SwiftUI

struct RootView: View {
    @Environment(Plate.self) private var plate

    @State private var path = NavigationPath()
    @State private var showingPlate = false
    @State private var showingToday = false

    var body: some View {
        NavigationStack(path: $path) {
            LocationsScreen(onOpenToday: { showingToday = true })
                .navigationDestination(for: DiningLocation.self) { location in
                    MenuScreen(location: location)
                }
        }
        // The tray bar sits outside the navigation stack so the running plate
        // stays underfoot on every screen — you build a plate while walking the
        // line, and the line runs through more than one room now that every
        // campus food spot is reachable.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TrayBar(onOpen: { showingPlate = true })
        }
        .sheet(isPresented: $showingPlate) { PlateScreen() }
        .sheet(isPresented: $showingToday) { TodayScreen() }
    }
}

#Preview {
    RootView()
        .environment(AppServices.preview())
        .environment(Plate())
        .ticketBackground()
}
