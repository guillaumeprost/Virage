import Foundation

/// The Watch's own settings: everything here plays on the wrist.
enum WatchSettings {
    static let guidanceHapticsKey = "guidanceHaptics"
    static let speedAlertKey = "speedAlert"
    /// In meters per second, whatever the display unit.
    static let speedLimitKey = "speedLimit"
    static let avoidsTollsKey = "avoidsTolls"
    static let placesKey = "places"

    /// 90 km/h.
    static let defaultSpeedLimit = 25.0

    static var guidanceHaptics: Bool {
        UserDefaults.standard.object(forKey: guidanceHapticsKey) as? Bool ?? true
    }

    /// The limit, or `nil` when the alert is off.
    static var speedLimit: Double? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: speedAlertKey) else { return nil }
        return defaults.object(forKey: speedLimitKey) as? Double ?? defaultSpeedLimit
    }

    static var places: [SavedPlace] {
        guard let data = UserDefaults.standard.data(forKey: placesKey) else { return [] }
        return (try? JSONDecoder().decode([SavedPlace].self, from: data)) ?? []
    }

    static func save(_ places: [SavedPlace]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(places), forKey: placesKey)
    }
}
