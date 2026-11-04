import ActivityKit
import Foundation

/// Keeps the lock screen and the Dynamic Island in step with the ride.
@MainActor
final class RideLiveActivityController {
    /// The activity is not sendable, so only its identifier is kept here; each update looks it up afresh.
    private var activityID: String?
    private var lastState: RideActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    /// The sensors report 25 times a second; the lock screen needs one.
    private let minimumInterval: TimeInterval = 1

    init() {
        // An activity left over from a crash or a forced quit would stay on the lock screen for hours.
        Task {
            for activity in Activity<RideActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func start(state: RideActivityAttributes.ContentState) {
        guard activityID == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activityID = try? Activity.request(
            attributes: RideActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        ).id
        lastState = state
        lastUpdate = .now
    }

    /// Only what the rider would see change is sent, and at most once a second.
    func update(_ state: RideActivityAttributes.ContentState) {
        // A pause starting or ending shows at once: the timer has to stop or restart with it.
        let pauseChanged = (state.pausedTime == nil) != (lastState?.pausedTime == nil)
        guard let activityID, state != lastState,
              pauseChanged || Date.now.timeIntervalSince(lastUpdate) >= minimumInterval else { return }
        lastState = state
        lastUpdate = .now
        Task { await Self.send(state, to: activityID) }
    }

    func end() {
        guard let activityID else { return }
        self.activityID = nil
        lastState = nil
        Task { await Self.end(activityID) }
    }

    private nonisolated static func send(_ state: RideActivityAttributes.ContentState, to id: String) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    private nonisolated static func end(_ id: String) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
