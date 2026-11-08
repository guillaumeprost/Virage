import Foundation

/// What is left in the tank, counted from the kilometers ridden since the last fill-up.
///
/// There is no fuel sensor to read: the rider gives the range of a full tank, and taps "Plein fait" at the pump.
struct FuelGauge: Equatable, Sendable {
    /// Meters on a full tank.
    var range: Double
    /// Meters left at which the rider is warned.
    var reserve: Double
    /// Meters ridden since the last fill-up.
    var sinceRefuel: Double

    var remaining: Double { max(range - sinceRefuel, 0) }

    var isLow: Bool { remaining <= reserve }

    /// Counts a stretch ridden. True when it just crossed into the reserve: the moment to warn, once per tank.
    mutating func add(_ meters: Double) -> Bool {
        guard meters > 0 else { return false }
        let wasLow = isLow
        sinceRefuel += meters
        return isLow && !wasLow
    }

    mutating func refuel() {
        sinceRefuel = 0
    }
}

/// The rider's settings, and the count kept between rides.
enum FuelSettings {
    static let enabledKey = "fuelEnabled"
    static let rangeKey = "fuelRange"
    static let reserveKey = "fuelReserve"
    static let sinceRefuelKey = "fuelSinceRefuel"

    /// In kilometers, as typed in the settings.
    static let defaultRangeKilometers = 250.0
    static let defaultReserveKilometers = 50.0

    /// `nil` when the rider does not track the tank.
    static func load(from defaults: UserDefaults = .standard) -> FuelGauge? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let range = (defaults.object(forKey: rangeKey) as? Double ?? defaultRangeKilometers) * 1_000
        let reserve = (defaults.object(forKey: reserveKey) as? Double ?? defaultReserveKilometers) * 1_000
        return FuelGauge(range: range, reserve: min(reserve, range), sinceRefuel: loadSinceRefuel(from: defaults))
    }

    static func loadSinceRefuel(from defaults: UserDefaults = .standard) -> Double {
        defaults.double(forKey: sinceRefuelKey)
    }

    static func save(sinceRefuel: Double, to defaults: UserDefaults = .standard) {
        defaults.set(sinceRefuel, forKey: sinceRefuelKey)
    }
}

/// The kilometers since the fill-up, counted with or without a tracked tank, and kept on disk every few hundred
/// meters rather than at every fix: losing a few hundred meters to a crash is fine for a trip counter.
struct RefuelOdometer {
    static let saveInterval = 500.0

    private(set) var meters: Double
    /// The count as last written.
    private var saved: Double
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        meters = FuelSettings.loadSinceRefuel(from: defaults)
        saved = meters
    }

    mutating func add(_ distance: Double) {
        guard distance > 0 else { return }
        meters += distance
        if meters - saved >= Self.saveInterval {
            save()
        }
    }

    /// At the pump: back to zero, written at once.
    mutating func reset() {
        meters = 0
        save()
    }

    /// At a pause, the end of a ride, or when the app leaves the screen.
    mutating func save() {
        guard meters != saved else { return }
        FuelSettings.save(sinceRefuel: meters, to: defaults)
        saved = meters
    }
}
