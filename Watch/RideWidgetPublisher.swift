import Foundation
import WidgetKit

/// Keeps the complications in step with the ride without spending the reload budget.
///
/// A new turn, the start or the end of a ride are shown at once; the distance ridden, at most once a minute.
@MainActor
final class RideWidgetPublisher {
    private var published = RideWidgetState.load()
    private var lastReload = Date.distantPast

    static let minimumInterval: TimeInterval = 5
    static let routineInterval: TimeInterval = 60

    func publish(_ state: RideWidgetState) {
        guard state != published else { return }
        let elapsed = Date.now.timeIntervalSince(lastReload)
        let isImportant = state.isRiding != published.isRiding
            || state.isPaused != published.isPaused
            || state.startDate != published.startDate
            || state.navigation?.symbol != published.navigation?.symbol
            || state.navigation?.instruction != published.navigation?.instruction
        guard isImportant ? elapsed >= Self.minimumInterval || state.isRiding != published.isRiding : elapsed >= Self.routineInterval else {
            return
        }
        published = state
        lastReload = .now
        state.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
