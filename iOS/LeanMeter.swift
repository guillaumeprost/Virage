import CoreMotion

/// Streams the yaw rate around the true vertical, smoothed to filter out engine vibrations.
@MainActor
final class LeanMeter {
    private let motionManager = CMMotionManager()
    private var smoothedYawRate = 0.0
    /// Low-pass factor at 25 Hz: about a third of a second to settle.
    private let smoothing = 0.15

    func start(_ onUpdate: @escaping @MainActor @Sendable (Double) -> Void) {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 25
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let rotation = motion.rotationRate
            let gravity = motion.gravity
            MainActor.assumeIsolated {
                guard let self else { return }
                let yawRate = LeanAngle.yawRate(
                    rotationRate: SIMD3(rotation.x, rotation.y, rotation.z),
                    gravity: SIMD3(gravity.x, gravity.y, gravity.z)
                )
                self.smoothedYawRate += (yawRate - self.smoothedYawRate) * self.smoothing
                onUpdate(self.smoothedYawRate)
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        smoothedYawRate = 0
    }
}
