import Foundation

enum SpeedUnit: String, CaseIterable, Identifiable, Sendable, Codable {
    case kilometersPerHour
    case milesPerHour

    static let storageKey = "speedUnit"

    static var current: SpeedUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SpeedUnit.init(rawValue:)) ?? .kilometersPerHour
    }

    var id: Self { self }

    var speedLabel: String {
        switch self {
        case .kilometersPerHour: "km/h"
        case .milesPerHour: "mph"
        }
    }

    var distanceLabel: String {
        switch self {
        case .kilometersPerHour: "km"
        case .milesPerHour: "mi"
        }
    }

    /// Converts from meters per second.
    func speed(_ metersPerSecond: Double) -> Double {
        switch self {
        case .kilometersPerHour: metersPerSecond * 3.6
        case .milesPerHour: metersPerSecond * 2.236_936
        }
    }

    /// Converts from meters.
    func distance(_ meters: Double) -> Double {
        switch self {
        case .kilometersPerHour: meters / 1_000
        case .milesPerHour: meters / 1_609.344
        }
    }
}

enum Format {
    static func speed(_ metersPerSecond: Double, _ unit: SpeedUnit) -> String {
        String(Int(unit.speed(metersPerSecond).rounded()))
    }

    static func distance(_ meters: Double, _ unit: SpeedUnit) -> String {
        String(format: "%.1f %@", unit.distance(meters), unit.distanceLabel)
    }

    /// "1 annonce", "12 annonces": the calls the guidance will make.
    static func announcements(_ count: Int) -> String {
        count == 1 ? "1 annonce" : "\(count) annonces"
    }

    /// What is left in the tank: whole kilometers, as on the bike's own display.
    static func range(_ meters: Double, _ unit: SpeedUnit) -> String {
        "\(Int(unit.distance(meters).rounded())) \(unit.distanceLabel)"
    }

    /// Distance to a turn: rounded to 10 m (or 50 ft) up close, where the rider needs precision.
    static func shortDistance(_ meters: Double, _ unit: SpeedUnit) -> String {
        switch unit {
        case .kilometersPerHour:
            meters < 1_000 ? "\(Int((meters / 10).rounded()) * 10) m" : String(format: "%.1f km", meters / 1_000)
        case .milesPerHour:
            meters < 304.8 ? "\(Int((meters * 3.280_84 / 50).rounded()) * 50) ft" : String(format: "%.1f mi", meters / 1_609.344)
        }
    }

    static func altitude(_ meters: Double?, _ unit: SpeedUnit) -> String {
        guard let meters else { return "—" }
        return switch unit {
        case .kilometersPerHour: "\(Int(meters.rounded())) m"
        case .milesPerHour: "\(Int((meters * 3.280_84).rounded())) ft"
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }

    /// "2 h 05 min": a ride's length, without seconds.
    static func shortDuration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    static func lean(_ degrees: Double) -> String {
        "\(Int(abs(degrees).rounded()))°"
    }

    static func course(_ degrees: Double?) -> String {
        guard let degrees else { return "—" }
        let points = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let index = Int((degrees / 45).rounded()) % points.count
        return "\(points[index]) \(Int(degrees.rounded()))°"
    }
}
