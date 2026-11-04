import WatchKit

/// Taps on the wrist, readable through a jacket sleeve and gloves without looking at the screen.
///
/// Left and right turns have their own patterns, so the direction is felt before the screen is read.
enum Haptics {
    @MainActor
    static func play(_ cue: GuidanceCue) {
        let device = WKInterfaceDevice.current()
        switch cue {
        case .prepare(let maneuver):
            device.play(pattern(for: maneuver))
        case .turn(let maneuver):
            // Twice, so "turn now" cannot be mistaken for the earlier warning.
            let pattern = pattern(for: maneuver)
            device.play(pattern)
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                device.play(pattern)
            }
        case .offRoute:
            device.play(.retry)
        case .arrived:
            device.play(.success)
        }
    }

    /// Unlike every guidance pattern, so it is never taken for a turn.
    @MainActor
    static func playSpeedAlert() {
        let device = WKInterfaceDevice.current()
        device.play(.failure)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            device.play(.failure)
        }
    }

    private static func pattern(for maneuver: Maneuver) -> WKHapticType {
        switch maneuver {
        case .slightLeft, .left, .sharpLeft: .navigationLeftTurn
        case .slightRight, .right, .sharpRight: .navigationRightTurn
        case .straight, .uTurn, .waypoint, .arrive: .navigationGenericManeuver
        }
    }
}
