import CoreLocation
import Testing
@testable import Virage

struct RideStatsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fix `meters` north of a fixed origin, `seconds` after the start.
    private func fix(meters: Double, seconds: TimeInterval, speed: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 45 + meters / 111_132, longitude: 5),
            altitude: 200,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: 0,
            speed: speed,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    @Test func accumulatesDistanceAndSpeedsWhileRiding() {
        var stats = RideStats()
        stats.start(at: start)
        stats.ingest(fix(meters: 0, seconds: 0, speed: 20))
        stats.ingest(fix(meters: 20, seconds: 1, speed: 20))
        stats.ingest(fix(meters: 50, seconds: 2, speed: 30))

        #expect(abs(stats.snapshot.distance - 50) < 0.5)
        #expect(stats.snapshot.movingTime == 2)
        #expect(stats.snapshot.maxSpeed == 30)
        #expect(abs(stats.snapshot.averageSpeed - 25) < 0.5)
        #expect(stats.snapshot.altitude == 200)
    }

    @Test func countsNothingWhilePaused() {
        var stats = RideStats()
        stats.start(at: start)
        stats.ingest(fix(meters: 0, seconds: 0, speed: 20))
        stats.ingest(fix(meters: 20, seconds: 1, speed: 20))
        stats.pause(at: start.addingTimeInterval(1))
        // Pushed to the café at a walk... or the GPS jumping: none of it counts.
        stats.ingest(fix(meters: 300, seconds: 61, speed: 35))
        stats.unpause(at: start.addingTimeInterval(61))
        stats.ingest(fix(meters: 320, seconds: 62, speed: 20))

        #expect(abs(stats.snapshot.distance - 20) < 0.5)
        #expect(stats.snapshot.maxSpeed == 20)
        // The live speed still follows the bike.
        #expect(stats.snapshot.speed == 20)
    }

    @Test func leavesPausesOutOfTheRideTime() {
        var stats = RideStats()
        stats.start(at: start)
        stats.pause(at: start.addingTimeInterval(600))
        #expect(stats.snapshot.isPaused)
        #expect(stats.snapshot.elapsed(at: start.addingTimeInterval(900)) == 600)

        stats.unpause(at: start.addingTimeInterval(900))
        #expect(stats.snapshot.elapsed(at: start.addingTimeInterval(1_000)) == 700)
        #expect(stats.snapshot.timerStart == start.addingTimeInterval(300))

        // Ending a ride while paused closes the pause.
        stats.pause(at: start.addingTimeInterval(1_000))
        stats.stop(at: start.addingTimeInterval(1_100))
        #expect(!stats.snapshot.isPaused)
        #expect(stats.snapshot.pausedDuration == 400)
    }

    @Test func ignoresJitterWhileStopped() {
        var stats = RideStats()
        stats.start(at: start)
        stats.ingest(fix(meters: 0, seconds: 0, speed: 0))
        stats.ingest(fix(meters: 3, seconds: 1, speed: 0.4))

        #expect(stats.snapshot.distance == 0)
        #expect(stats.snapshot.movingTime == 0)
    }

    @Test func rejectsImpreciseAndImplausibleFixes() {
        var stats = RideStats()
        stats.start(at: start)

        let imprecise = stats.ingest(fix(meters: 0, seconds: 0, speed: 20, accuracy: 80))
        let implausible = stats.ingest(fix(meters: 0, seconds: 0, speed: 200))

        #expect(!imprecise)
        #expect(!implausible)
        #expect(stats.snapshot.maxSpeed == 0)
    }

    @Test func derivesSpeedWhenTheReceiverGivesNone() {
        var stats = RideStats()
        stats.ingest(fix(meters: 0, seconds: 0, speed: -1))
        stats.ingest(fix(meters: 25, seconds: 1, speed: -1))

        #expect(abs(stats.snapshot.speed - 25) < 0.5)
    }

    @Test func showsLiveSpeedWithoutRecordingOutsideARide() {
        var stats = RideStats()
        stats.ingest(fix(meters: 0, seconds: 0, speed: 20))
        stats.ingest(fix(meters: 20, seconds: 1, speed: 25))

        #expect(stats.snapshot.speed == 25)
        #expect(stats.snapshot.distance == 0)
        #expect(stats.snapshot.maxSpeed == 0)
    }

    @Test func keepsLeanPeaksPerSide() {
        var stats = RideStats()
        stats.start(at: start)
        stats.recordLean(32)
        stats.recordLean(-41)
        stats.recordLean(12)

        #expect(stats.snapshot.leanAngle == 12)
        #expect(stats.snapshot.maxLeanRight == 32)
        #expect(stats.snapshot.maxLeanLeft == 41)
    }

    @Test func resumesFromAnotherDevice() {
        var phone = RideSnapshot(isRiding: true, distance: 1_000, leanAngle: 20, movingTime: 60)
        phone.maxSpeed = 30
        var stats = RideStats()
        stats.resume(from: phone)
        stats.ingest(fix(meters: 0, seconds: 0, speed: 20))
        stats.ingest(fix(meters: 20, seconds: 1, speed: 20))

        #expect(abs(stats.snapshot.distance - 1_020) < 0.5)
        #expect(stats.snapshot.movingTime == 61)
        #expect(stats.snapshot.maxSpeed == 30)
        #expect(stats.snapshot.leanAngle == 0)
    }
}

struct LeanAngleTests {
    @Test func matchesTheSteadyTurnFormula() {
        // 20 m/s on a 60 m radius: ω = v / r, tan(lean) = v² / (r·g) ≈ 0.68, so about 34°.
        let degrees = LeanAngle.degrees(speed: 20, yawRate: 20.0 / 60)
        #expect(abs(degrees - 34.2) < 0.5)
    }

    @Test func isZeroAtWalkingPace() {
        #expect(LeanAngle.degrees(speed: 2, yawRate: 1) == 0)
    }

    @Test func isClampedToARealisticLean() {
        #expect(LeanAngle.degrees(speed: 60, yawRate: 3) == LeanAngle.maximumDegrees)
    }

    @Test func turnsRightWhenRotatingClockwiseSeenFromAbove() {
        // Phone upright in portrait: gravity along -y. Clockwise from above is a positive rotation around -y.
        let gravity = SIMD3<Double>(0, -1, 0)
        #expect(LeanAngle.yawRate(rotationRate: SIMD3(0, -0.5, 0), gravity: gravity) == 0.5)
        #expect(LeanAngle.yawRate(rotationRate: SIMD3(0, 0.5, 0), gravity: gravity) == -0.5)
    }
}
