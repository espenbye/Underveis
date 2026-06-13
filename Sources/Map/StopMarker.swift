import SwiftUI

/// A small, neutral marker for a transit stop. Deliberately subdued (system background + a thin
/// ring) so the colourful, larger vehicle markers stay the focus.
struct StopMarker: View {
    let stop: Stop

    var body: some View {
        Image(systemName: stop.symbolName)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .background(.background, in: Circle())
            .overlay(Circle().strokeBorder(.secondary.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            .accessibilityLabel(stop.name)
    }
}
