import SwiftUI

/// The Beeline-style screen: one big arrow in a ring that closes as the turn nears, the distance, the street,
/// and what is left to the destination.
struct WatchNavigationView: View {
    let state: GuidanceState
    let snapshot: RideSnapshot
    let unit: SpeedUnit
    let isRerouting: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 6)
                if state.mode == .route, !isRerouting, !state.isOffRoute {
                    Circle()
                        .trim(from: 0, to: state.maneuverProgress)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.5), value: state.maneuverProgress)
                }
                GuidanceArrow(state: state, course: snapshot.course)
                    .font(.system(size: 52, weight: .bold))
            }
            .padding(3)
            .frame(maxHeight: .infinity)

            Text(state.hasArrived ? "Arrivé" : Format.shortDistance(state.distanceToManeuver, unit))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(caption)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if !state.hasArrived {
                remaining
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
    }

    /// The whole trip at a glance: distance left and, with a route, the time of arrival.
    private var remaining: some View {
        HStack(spacing: 4) {
            Text(Format.shortDistance(state.remainingDistance, unit))
            if let arrival = state.arrivalDate(from: .now) {
                Text("·")
                Image(systemName: "flag.checkered")
                Text(arrival, style: .time)
            }
        }
    }

    private var caption: String {
        if state.isOffRoute, state.followsTrack {
            return "Rejoins la trace"
        }
        if isRerouting || state.isOffRoute {
            return "Recalcul…"
        }
        if state.hasArrived || state.mode == .compass {
            return state.destinationName
        }
        return state.instruction
    }
}
