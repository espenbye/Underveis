import SwiftUI

/// A small, neutral marker for a transit stop. Deliberately subdued (system background + a thin
/// ring) so the colourful, larger vehicle markers stay the focus.
struct StopMarker: View {
    let stop: Stop
    var isSelected: Bool = false

    var body: some View {
        Image(systemName: stop.symbolName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: 20, height: 20)
            .background(.background, in: Circle())
            .overlay(
                Circle().strokeBorder(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary.opacity(0.45)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            .scaleEffect(isSelected ? 1.4 : 1)
            .animation(.snappy, value: isSelected)
            .accessibilityLabel(stop.name)
    }
}
