import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What the home and lock screen widgets show, written by the app into the shared App Group.
struct HomeWidgetState: Codable, Equatable {
    struct LastTrip: Codable, Equatable {
        var date: Date
        var distance: Double
        var movingTime: TimeInterval
        var elevationGain: Double
    }

    struct Month: Codable, Equatable {
        var start: Date
        var count: Int
        var distance: Double
        var movingTime: TimeInterval
    }

    /// Meters since the last fill-up.
    var sinceRefuel: Double
    /// Meters left and on a full tank, when the rider tracks the range.
    var fuelRemaining: Double?
    var fuelRange: Double?
    var isFuelLow: Bool
    var lastTrip: LastTrip?
    var month: Month
    var unit: SpeedUnit

    static let kind = "VirageHome"
    static let suiteName = "group.com.guillaumeprost.Virage"
    private static let key = "homeWidgetState"

    static let placeholder = HomeWidgetState(
        sinceRefuel: 142_300,
        fuelRemaining: nil,
        fuelRange: nil,
        isFuelLow: false,
        lastTrip: LastTrip(date: .now.addingTimeInterval(-86_400), distance: 87_400, movingTime: 5_400, elevationGain: 1_240),
        month: Month(start: .now, count: 6, distance: 412_000, movingTime: 7 * 3_600),
        unit: .kilometersPerHour
    )

    static func load() -> HomeWidgetState? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HomeWidgetState.self, from: data)
    }

    #if os(watchOS)
    /// On the Watch, the figures show in the ride complication.
    private static let reloadedKind = "RideComplication"
    #else
    private static let reloadedKind = kind
    #endif

    /// Writes the state and has the widgets that show it redrawn, only when something they show changed.
    func save() {
        guard self != Self.load(), let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.suiteName)?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.reloadedKind)
        #endif
    }
}

extension HomeWidgetState {
    /// The range left when tracked, otherwise the trip counter.
    var tank: (value: String, caption: String) {
        if let fuelRemaining {
            return (Format.range(fuelRemaining, unit), "d'autonomie")
        }
        return (Format.distance(sinceRefuel, unit), "depuis le plein")
    }

    var fuelSymbol: String {
        isFuelLow ? "fuelpump.exclamationmark.fill" : "fuelpump.fill"
    }

    /// What is left out of a full tank, when the range is tracked.
    var gauge: (remaining: Double, range: Double)? {
        guard let fuelRemaining, let fuelRange, fuelRange > 0 else { return nil }
        return (min(fuelRemaining, fuelRange), fuelRange)
    }

    /// "142": whole kilometers or miles, for the round slots.
    func wholeDistance(_ meters: Double) -> String {
        "\(Int(unit.distance(meters).rounded()))"
    }

    /// "142.3 km · mois 412 km", on one line.
    var inlineCaption: String {
        "\(tank.value) · mois \(Format.range(month.distance, unit))"
    }

    /// "6 trajets · 412 km"
    var monthCaption: String {
        "\(month.count) \(month.count == 1 ? "trajet" : "trajets") · \(Format.range(month.distance, unit))"
    }

    /// The figures as they read on a given day: once the month has turned, its total starts again from zero.
    func asOf(_ date: Date, calendar: Calendar = .current) -> HomeWidgetState {
        guard !calendar.isDate(month.start, equalTo: date, toGranularity: .month) else { return self }
        var state = self
        state.month = Month(start: calendar.dateInterval(of: .month, for: date)?.start ?? date, count: 0, distance: 0, movingTime: 0)
        return state
    }

    /// The figures now, then from the first of next month: nothing else changes them without the app.
    func timeline(from date: Date, calendar: Calendar = .current) -> [(date: Date, state: HomeWidgetState)] {
        let now = asOf(date, calendar: calendar)
        guard let next = calendar.dateInterval(of: .month, for: date)?.end else { return [(date, now)] }
        return [(date, now), (next, asOf(next, calendar: calendar))]
    }
}
