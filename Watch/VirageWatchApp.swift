import HealthKit
import SwiftUI
import WatchKit
#if DEBUG
import WidgetKit
#endif

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
        #if DEBUG
        // -demoHome YES: the iPhone's figures without an iPhone, to check the complications in the simulator.
        if UserDefaults.standard.bool(forKey: "demoHome") {
            var home = HomeWidgetState.placeholder
            if UserDefaults.standard.bool(forKey: "demoFuel") {
                home.fuelRange = 250_000
                home.fuelRemaining = 87_600
            }
            home.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchRideModel.shared.handleWorkoutLaunch()
    }
}
