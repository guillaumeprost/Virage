import Foundation
import simd

/// Lean angle from the turn rate rather than from the gravity direction.
///
/// In a steady turn the bike leans so that gravity and centripetal force add up along its own axis: the
/// accelerometer then reads "straight down" whatever the lean, and a gravity-based angle stays near zero.
/// The balance condition gives the lean directly instead: tan(lean) = v · ω / g, with v the speed and ω the
/// yaw rate around the vertical. It does not depend on how the phone is mounted.
enum LeanAngle {
    /// Below ~10 km/h, the bike is balanced by the rider rather than by the turn and the formula is meaningless.
    static let minimumSpeed: Double = 3
    static let maximumDegrees: Double = 65
    static let standardGravity = 9.806_65

    /// Rotation rate around the true vertical, in rad/s, positive when turning right (clockwise seen from above).
    ///
    /// Both vectors are in the device frame. Gravity points down, so a right-handed rotation around it is clockwise.
    static func yawRate(rotationRate: SIMD3<Double>, gravity: SIMD3<Double>) -> Double {
        let length = simd_length(gravity)
        guard length > 0.1 else { return 0 }
        return simd_dot(rotationRate, gravity / length)
    }

    /// Lean in degrees, positive to the right.
    static func degrees(speed: Double, yawRate: Double) -> Double {
        guard speed >= minimumSpeed else { return 0 }
        let degrees = atan(speed * yawRate / standardGravity) * 180 / .pi
        return min(max(degrees, -maximumDegrees), maximumDegrees)
    }
}
