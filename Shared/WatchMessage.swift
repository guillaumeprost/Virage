import Foundation
import HealthKit

/// Messages exchanged between the iPhone and the Watch through WatchConnectivity.
enum WatchMessage {
    enum Command: String, Sendable {
        case start
        case stop
        /// Ends the guidance but not the ride.
        case stopNavigation
        case pause
        case resume
        /// Goes on to the stop after the next one, or to the destination.
        case skipStop
        /// Sent by the Watch when it (re)connects: a relaunched Watch app has lost the route, and may have
        /// missed the latest places.
        case requestRoute
    }

    private static let snapshotKey = "snapshot"
    private static let unitKey = "unit"
    private static let commandKey = "command"

    private static let sentAtKey = "sentAt"
    /// An iPhone ride older than this is no proof the iPhone is still riding.
    static let maxRideAge: TimeInterval = 10

    static func payload(_ snapshot: RideSnapshot, unit: SpeedUnit, at date: Date = .now) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        return [snapshotKey: data, unitKey: unit.rawValue, sentAtKey: date.timeIntervalSince1970]
    }

    /// A ride in progress that is not recent is dropped: the application context replays the last state sent,
    /// and an iPhone app closed mid-ride would otherwise start a phantom ride on the Watch at every launch.
    static func snapshot(in message: [String: Any], now: Date = .now) -> (RideSnapshot, SpeedUnit)? {
        guard
            let data = message[snapshotKey] as? Data,
            let snapshot = try? JSONDecoder().decode(RideSnapshot.self, from: data)
        else { return nil }
        if snapshot.isRiding {
            let sentAt = (message[sentAtKey] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
            guard now.timeIntervalSince(sentAt) <= maxRideAge else { return nil }
        }
        let unit = (message[unitKey] as? String).flatMap(SpeedUnit.init(rawValue:)) ?? .kilometersPerHour
        return (snapshot, unit)
    }

    static func payload(_ command: Command) -> [String: Any] {
        [commandKey: command.rawValue]
    }

    static func command(in message: [String: Any]) -> Command? {
        (message[commandKey] as? String).flatMap(Command.init(rawValue:))
    }

    private static let placesKey = "places"

    /// Sent as user info: queued and delivered even when the Watch app is not running.
    static func payload(_ places: [SavedPlace]) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(places) else { return nil }
        return [placesKey: data]
    }

    static func places(in userInfo: [String: Any]) -> [SavedPlace]? {
        guard let data = userInfo[placesKey] as? Data else { return nil }
        return try? JSONDecoder().decode([SavedPlace].self, from: data)
    }

    /// Files go both ways: routes to the Watch, trips recorded on the Watch to the iPhone.
    enum FileKind: String {
        case route, trip
    }

    private static let fileKindKey = "kind"

    static func metadata(_ kind: FileKind) -> [String: Any] {
        [fileKindKey: kind.rawValue]
    }

    static func fileKind(in metadata: [String: Any]?) -> FileKind? {
        (metadata?[fileKindKey] as? String).flatMap(FileKind.init(rawValue:))
    }
}

extension HKWorkoutConfiguration {
    /// HealthKit has no motorcycle activity. The session only keeps the Watch app awake and is never saved.
    static var motorcycleRide: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .outdoor
        return configuration
    }
}
