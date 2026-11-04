import HealthKit
import SwiftUI
import WatchKit

@main
struct VirageWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environment(WatchRideModel.shared)
                // The iPhone app's system blue; without an asset catalog the Watch's accent would be grey.
                .tint(.blue)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchRideModel.shared.activate()
        WatchRideModel.shared.requestPermissions()
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchRideModel.shared.handleWorkoutLaunch()
    }
}
