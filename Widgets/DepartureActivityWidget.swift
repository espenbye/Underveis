#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// The departure-countdown Live Activity: a Lock Screen banner plus the Dynamic Island presentations,
/// all rendering a self-advancing countdown to the predicted departure (no push updates needed).
struct DepartureActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            DepartureLockScreenView(attributes: context.attributes, state: context.state)
                .padding()
                .activityBackgroundTint(.black.opacity(0.5))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LineBadge(
                        code: context.attributes.linePublicCode,
                        colourHex: context.attributes.colourHex,
                        textColourHex: context.attributes.textColourHex
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).font(.title2.weight(.bold)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.destination) · \(context.attributes.stopName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } compactLeading: {
                LineBadge(
                    code: context.attributes.linePublicCode,
                    colourHex: context.attributes.colourHex,
                    textColourHex: context.attributes.textColourHex
                )
            } compactTrailing: {
                countdown(context.state).monospacedDigit()
            } minimal: {
                countdown(context.state).monospacedDigit()
            }
        }
    }

    /// Shared countdown rendering for every Dynamic Island region: a live timer, "Nå", or "Innstilt".
    @ViewBuilder
    private func countdown(_ state: DepartureActivityAttributes.ContentState) -> some View {
        if state.isCancelled {
            Text("Innstilt").foregroundStyle(.red)
        } else if state.expectedDeparture > .now {
            Text(timerInterval: Date.now...state.expectedDeparture, countsDown: true)
        } else {
            Text("Nå")
        }
    }
}

/// The Lock Screen / banner presentation: line badge, destination + stop, and the countdown.
private struct DepartureLockScreenView: View {
    let attributes: DepartureActivityAttributes
    let state: DepartureActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(
                code: attributes.linePublicCode,
                colourHex: attributes.colourHex,
                textColourHex: attributes.textColourHex
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.destination).font(.headline).lineLimit(1)
                Text(attributes.stopName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                trailing
                if state.delayMinutes > 0 {
                    Text("\(state.delayMinutes) min forsinket")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if state.isCancelled {
            Text("Innstilt").font(.headline).foregroundStyle(.red)
        } else if state.expectedDeparture > .now {
            Text(timerInterval: Date.now...state.expectedDeparture, countsDown: true)
                .font(.title2.weight(.bold)).monospacedDigit().frame(minWidth: 56)
        } else {
            Text("Nå").font(.title2.weight(.bold))
        }
    }
}

/// A small coloured line-number badge, shared by the Lock Screen view and the Dynamic Island.
private struct LineBadge: View {
    let code: String
    let colourHex: String?
    let textColourHex: String?

    var body: some View {
        Text(code)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(enturHex: textColourHex) ?? .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Color(enturHex: colourHex) ?? .accentColor,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}
#endif
