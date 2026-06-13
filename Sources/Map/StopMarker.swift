import SwiftUI

/// A small, glass-backed marker for a transit stop. Deliberately subdued so the colourful,
/// larger vehicle markers stay the focus.
struct StopMarker: View {
    let stop: Stop
    var isSelected: Bool = false

    private var stopTint: Color {
        isSelected ? .accentColor : .secondary
    }

    var body: some View {
        Image(systemName: stop.symbolName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: 18, height: 18)
            .glassEffect(.regular.tint(stopTint.opacity(isSelected ? 0.24 : 0.12)), in: Circle())
            .overlay(
                Circle().strokeBorder(
                    isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.95)) : AnyShapeStyle(.secondary.opacity(0.45)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .shadow(color: .black.opacity(0.16), radius: isSelected ? 2.5 : 1, y: 0.5)
            .scaleEffect(isSelected ? 1.25 : 1)
            .animation(.snappy, value: isSelected)
            .accessibilityLabel(stop.name)
    }
}
