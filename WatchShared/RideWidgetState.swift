import Foundation

/// What the watch face shows of the ride, written by the Watch app for its complications.
///
/// Only figures that stay true between two reloads: a complication is refreshed a few times a minute at
/// best, so it shows the street and the time of arrival rather than a distance that would go stale.
struct RideWidgetState: Codable, Equatable, Sendable {
    struct Navigation: Codable, Equatable, Sendable {
        var symbol: String
        var instruction: String
        var arrival: Date?
    }

    var isRiding = false
    var startDate: Date?
    var distance = ""
    var isPaused = false
    var navigation: Navigation?

    static let appGroup = "group.com.guillaumeprost.Virage"
    static let complicationKind = "RideComplication"
    private static let key = "rideWidgetState"

    static func load() -> RideWidgetState {
        guard
            let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
            let state = try? JSONDecoder().decode(RideWidgetState.self, from: data)
        else { return RideWidgetState() }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}
