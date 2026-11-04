import Foundation

/// Navigation on the iPhone: plans the route, sends it to the Watch, follows it, and reroutes.
///
/// While the iPhone is in reach it owns routing; the Watch only reroutes on its own once it has lost the iPhone.
@MainActor
@Observable
final class NavigationController {
    private(set) var guidance: Guidance?
    private(set) var isRerouting = false

    @ObservationIgnored private let connectivity: PhoneConnectivity
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private var lastPosition: Coordinate?
    /// A rider missing a turn keeps moving away; rerouting more often than this only burns requests.
    @ObservationIgnored private let rerouteInterval: TimeInterval = 15

    init(connectivity: PhoneConnectivity) {
        self.connectivity = connectivity
    }

    var state: GuidanceState? { guidance?.state }

    /// The stop the route goes through next, if any.
    var nextStop: Waypoint? { guidance?.remainingStops.first }

    /// The café is closed, the pass is shut: on to the following stop, or straight to the destination.
    func skipNextStop() {
        guard let guidance, nextStop != nil, !isRerouting else { return }
        let routeID = guidance.route.id
        let position = lastPosition
        isRerouting = true
        Task {
            defer { isRerouting = false }
            guard let newRoute = try? await guidance.routeSkippingNextStop(from: position),
                  self.guidance?.route.id == routeID else { return }
            start(newRoute, from: position)
        }
    }

    /// `position` fills the guidance right away instead of waiting for the next fix, which never comes while stopped.
    func start(_ route: NavigationRoute, from position: Coordinate?) {
        guidance = Guidance(route: route)
        connectivity.send(route: route)
        if let position {
            update(position)
        }
    }

    func stop() {
        guard guidance != nil else { return }
        guidance = nil
        isRerouting = false
        connectivity.send(route: nil)
    }

    func update(_ position: Coordinate) {
        lastPosition = position
        guard var guidance else { return }
        let cues = guidance.update(position)
        self.guidance = guidance
        if cues.contains(.offRoute) || (guidance.state.isOffRoute && !isRerouting) {
            reroute(from: position)
        }
    }

    private func reroute(from position: Coordinate) {
        guard let route = guidance?.route, route.mode == .route, !route.followsTrack, !isRerouting,
              Date.now.timeIntervalSince(lastReroute) >= rerouteInterval else { return }
        // A missed turn must not skip the stops still ahead.
        let remainingStops = guidance?.remainingStops ?? []
        isRerouting = true
        lastReroute = .now
        Task {
            defer { isRerouting = false }
            guard let newRoute = try? await RoutePlanner.route(
                to: route.destination,
                named: route.destinationName,
                via: remainingStops,
                from: position,
                avoidsTolls: route.avoidsTolls
            ) else { return }
            // Navigation may have been stopped while the request was in flight.
            guard guidance?.route.destination == route.destination else { return }
            start(newRoute, from: position)
        }
    }
}
