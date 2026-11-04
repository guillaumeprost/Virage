import Foundation
import Testing
@testable import Virage

struct SpeedAlertTests {
    /// Feeds speeds, one per second unless a time is given, and returns which of them warned.
    private func warnings(_ readings: [(speed: Double, second: Double)]) -> [Bool] {
        // 90 km/h.
        var alert = SpeedAlert(limit: 25)
        return readings.map { reading in
            alert.update(speed: reading.speed, at: Date(timeIntervalSince1970: reading.second))
        }
    }

    @Test func warnsOnceWhenCrossingTheLimit() {
        #expect(warnings([(24, 0), (26, 1), (27, 2)]) == [false, true, false])
    }

    @Test func ignoresHoveringAroundTheLimit() {
        // Just under, then over again: still the same excess.
        #expect(warnings([(26, 0), (24.5, 5), (25.5, 10)]) == [true, false, false])
    }

    @Test func warnsAgainAfterSlowingDownClearly() {
        #expect(warnings([(26, 0), (22, 5), (26, 10)]) == [true, false, true])
    }

    @Test func remindsWhileStayingOver() {
        #expect(warnings([(26, 0), (26, 59), (26, 61)]) == [true, false, true])
    }
}
