import SwiftUI
import WidgetKit

/// The widget extension's entry point. The configurable "Neste avgang" widget runs on iOS and macOS;
/// the departure-countdown Live Activity is iOS-only (ActivityKit doesn't exist on macOS).
@main
struct UnderveisWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextDepartureWidget()
        #if os(iOS)
            DepartureActivityWidget()
        #endif
    }
}
