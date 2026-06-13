import SwiftData
import SwiftUI

@main
struct BussradarApp: App {
    private let container: ModelContainer
    @State private var model: VehiclesModel

    init() {
        let container = Self.makeContainer()
        self.container = container
        let lineColors = LineColorStore(container: container)
        _model = State(initialValue: VehiclesModel(lineColors: lineColors))
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
        if let container = try? ModelContainer(for: CachedLine.self) {
            return container
        }
        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: CachedLine.self, configurations: memory) {
            return container
        }
        fatalError("Unable to create a SwiftData ModelContainer for CachedLine.")
    }
}
