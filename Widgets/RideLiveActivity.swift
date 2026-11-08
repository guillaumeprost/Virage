import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VirageWidgets: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
        HomeWidget()
    }
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpeedText(state: state, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let guidance = state.guidance {
                        ManeuverView(guidance: guidance, symbolSize: 30)
                            .padding(.trailing, 4)
                    } else {
                        Text(state.distance)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let guidance = state.guidance {
                        Text(guidance.instruction)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        RideTimeText(state: state)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Text(state.speed)
                    .font(.headline)
                    .monospacedDigit()
            } compactTrailing: {
                if let guidance = state.guidance {
                    HStack(spacing: 2) {
                        Image(systemName: guidance.symbol)
                        Text(guidance.distance)
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                } else if state.pausedTime != nil {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.speedUnit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                if let guidance = state.guidance {
                    Image(systemName: guidance.symbol)
                        .foregroundStyle(.tint)
                } else {
                    Text(state.speed)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        // Also shown in the Apple Watch's Smart Stack while the Virage app is not on screen.
        .supplementalActivityFamilies([.small, .medium])
    }
}

/// On the lock screen: the speed on the left, the next turn (or the trip so far) on the right.
private struct LockScreenView: View {
    @Environment(\.activityFamily) private var family
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if family == .small {
            WatchSmartStackView(state: state)
        } else {
            fullView
        }
    }

    private var fullView: some View {
        HStack(spacing: 16) {
            SpeedText(state: state, size: 52)
            Spacer(minLength: 0)
            if let guidance = state.guidance {
                VStack(alignment: .trailing, spacing: 4) {
                    ManeuverView(guidance: guidance, symbolSize: 34)
                    Text(guidance.instruction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(state.distance)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    RideTimeText(state: state)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding()
    }
}

/// The Watch's Smart Stack is small: the next turn if there is one, the speed in any case.
private struct WatchSmartStackView: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if let guidance = state.guidance {
                VStack(alignment: .leading, spacing: 2) {
                    ManeuverView(guidance: guidance, symbolSize: 24)
                    Text(guidance.instruction)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                SpeedText(state: state, size: 28)
            } else {
                SpeedText(state: state, size: 34)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.distance)
                        .font(.headline)
                        .monospacedDigit()
                    RideTimeText(state: state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

/// The ride time, pauses excluded: counted up by the system while riding, frozen while paused.
private struct RideTimeText: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if let pausedTime = state.pausedTime {
            Label(pausedTime, systemImage: "pause.fill")
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
        }
    }
}

private struct SpeedText: View {
    let state: RideActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(state.speed)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(state.speedUnit)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct ManeuverView: View {
    let guidance: RideActivityAttributes.Guidance
    let symbolSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: guidance.symbol)
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(.tint)
            Text(guidance.distance)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
