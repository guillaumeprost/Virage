import SwiftUI

/// The maneuver arrow in route mode; in compass mode, an arrow towards the destination relative to the
/// direction of travel.
struct GuidanceArrow: View {
    let state: GuidanceState
    let course: Double?

    var body: some View {
        if state.hasArrived {
            Image(systemName: Maneuver.arrive.symbolName)
                .foregroundStyle(.green)
        } else if state.mode == .compass {
            Image(systemName: "location.north.fill")
                .foregroundStyle(.tint)
                .rotationEffect(.degrees(Geo.turn(from: course ?? 0, to: state.bearingToDestination)))
                .animation(.easeOut(duration: 0.4), value: state.bearingToDestination)
        } else {
            Image(systemName: state.isOffRoute ? "arrow.triangle.2.circlepath" : state.maneuver.symbolName)
                .foregroundStyle(.tint)
        }
    }
}
