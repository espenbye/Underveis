import SwiftData
import SwiftUI

@main
struct UnderveisApp: App {
    private let container: ModelContainer
    @State private var model: VehiclesModel

    init() {
        let container = Self.makeContainer()
        self.container = container
        let lineColors = LineColorStore(container: container)
        let personalization = PersonalizationStore(container: container)
        _model = State(
            initialValue: VehiclesModel(lineColors: lineColors, personalization: personalization)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .modelContainer(container)
        #if os(macOS)
            .windowResizability(.contentSize)
            .defaultSize(width: 1100, height: 760)
        #endif
    }

    /// Prefer an on-disk store; fall back to in-memory so a corrupt store never blocks launch.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            CachedLine.self, FavoriteStop.self, WatchedLine.self, RecentStop.self, RecentLine.self,
        ])
        if let container = try? ModelContainer(for: schema) {
            return container
        }
        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: memory) {
            return container
        }
        fatalError("Unable to create a SwiftData ModelContainer for the app's models.")
    }
}
