import Foundation

/// Warns once when the speed goes over a limit, then again every so often while it stays over.
///
/// The speed has to drop clearly below the limit before crossing it again warns anew, so riding right at the
/// limit does not buzz at every GPS fix.
struct SpeedAlert: Sendable {
    /// In meters per second.
    var limit: Double
    /// Below the limit by this much (about 5 km/h), the alert is ready to fire again.
    static let rearmMargin = 1.4
    /// Still over the limit after this long, the rider is reminded.
    static let reminderInterval: TimeInterval = 60

    private(set) var isOver = false
    private var lastAlert = Date.distantPast

    init(limit: Double) {
        self.limit = limit
    }

    /// Returns `true` when the rider should be warned now.
    mutating func update(speed: Double, at date: Date) -> Bool {
        if isOver {
            if speed < limit - Self.rearmMargin {
                isOver = false
                return false
            }
            guard speed > limit, date.timeIntervalSince(lastAlert) >= Self.reminderInterval else { return false }
            lastAlert = date
            return true
        }
        guard speed > limit else { return false }
        isOver = true
        lastAlert = date
        return true
    }
}
