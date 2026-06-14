import SwiftUI
import WidgetKit

/// The configurable "Neste avgang" widget — bound to a favourite stop, showing its next departures
/// with a live countdown. Supports the home-screen system families and the Lock Screen accessories.
struct NextDepartureWidget: Widget {
    private let kind = "no.espenbye.underveis.NextDeparture"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectStopIntent.self,
            provider: NextDepartureProvider()
        ) { entry in
            NextDepartureView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Neste avgang")
        .description("Vis neste avganger fra en favorittholdeplass.")
        .supportedFamilies(Self.supportedFamilies)
    }

    /// The Lock Screen accessory families exist only on iOS; macOS gets the system families.
    private static var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
            [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        #else
            [.systemSmall, .systemMedium]
        #endif
    }
}
