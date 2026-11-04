import ActivityKit
import Foundation

/// The ride as shown on the lock screen and in the Dynamic Island.
///
/// The app formats every value before sending it: the widget extension then needs none of the app's code,
/// and shows exactly what the dashboard shows, in the rider's unit.
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var speed: String
        var speedUnit: String
        var distance: String
        /// Set while navigating.
        var guidance: Guidance?
        /// The ride start shifted by the pauses, which the system counts up from on its own between updates.
        var timerStart: Date
        /// The ride time, frozen, while paused.
        var pausedTime: String?
    }

    struct Guidance: Codable, Hashable {
        /// An SF Symbol: the maneuver arrow, or the flag on arrival.
        var symbol: String
        var distance: String
        var instruction: String
    }
}
