import SwiftUI
import SwiftData

@main
struct BoilerGrubApp: App {
    @State private var services = AppServices.live()
    @State private var plate = Plate()

    /// Built explicitly so a corrupt or migration-failed store degrades to an
    /// in-memory one instead of crashing on launch.
    private let container: ModelContainer = {
        let schema = Schema([LoggedPlate.self, LoggedItem.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .environment(plate)
                .ticketBackground()
        }
        .modelContainer(container)
    }
}
