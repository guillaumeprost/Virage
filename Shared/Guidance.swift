import Foundation

struct GuidanceState: Equatable, Sendable {
    var mode: NavigationMode
    var destinationName: String
    /// The next maneuver; `.straight` in compass mode.
    var maneuver: Maneuver = .straight
    var instruction = ""
    /// Meters to the next maneuver; to the destination in compass mode.
    var distanceToManeuver: Double = 0
    var remainingDistance: Double = 0
    /// Length of the stretch that ends at the next maneuver, for showing how much of it is behind.
    var stepLength: Double = 0
    /// Time left at the pace Apple Maps expects; `nil` in compass mode, which has no estimate.
    var remainingTime: TimeInterval?
    /// Degrees clockwise from north, from the rider to the destination.
    var bearingToDestination: Double = 0
    var isOffRoute = false
    var hasArrived = false
    /// Following a GPX track: off it, the rider is told to rejoin it rather than rerouted.
    var followsTrack = false

    /// How much of the stretch to the next maneuver is behind, from 0 to 1.
    var maneuverProgress: Double {
        guard stepLength > 0 else { return hasArrived ? 1 : 0 }
        return min(max(1 - distanceToManeuver / stepLength, 0), 1)
    }

    func arrivalDate(from now: Date) -> Date? {
        remainingTime.map { now.addingTimeInterval($0) }
    }
}

/// Moments worth a tap on the wrist.
enum GuidanceCue: Equatable, Sendable {
    case prepare(Maneuver)
    case turn(Maneuver)
    case offRoute
    case arrived
}

/// Follows the rider along a route. Pure value logic, run on whichever device has the location.
struct Guidance: Sendable {
    static let arrivalRadius = 30.0
    /// Farther than this from the route, a fix counts towards being off route.
    static let offRouteDistance = 60.0
    /// Consecutive far fixes before declaring the rider off route, so one bad fix does not trigger a reroute.
    static let offRouteFixes = 3
    static let prepareDistance = 300.0
    static let turnDistance = 40.0
    /// A maneuver this close behind the rider is considered done.
    static let passedTolerance = 5.0

    let route: NavigationRoute
    private(set) var state: GuidanceState
    private let cumulative: [Double]
    private var segmentIndex = 0
    private var farFixes = 0
    private var preparedSteps: Set<Int> = []
    private var turnedSteps: Set<Int> = []

    init(route: NavigationRoute) {
        self.route = route
        var cumulative = [0.0]
        for index in route.points.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + Geo.distance(route.points[index - 1], route.points[index]))
        }
        self.cumulative = cumulative
        state = GuidanceState(mode: route.mode, destinationName: route.destinationName, remainingDistance: route.distance)
        state.remainingTime = route.mode == .route ? route.expectedTravelTime : nil
        state.followsTrack = route.followsTrack
    }

    mutating func update(_ position: Coordinate) -> [GuidanceCue] {
        guard !state.hasArrived else { return [] }
        var cues: [GuidanceCue] = []
        let toDestination = Geo.distance(position, route.destination)
        state.bearingToDestination = Geo.bearing(position, route.destination)

        if route.mode == .compass || route.points.count < 2 {
            state.distanceToManeuver = toDestination
            state.remainingDistance = toDestination
        } else {
            let (along, offset) = locate(position)
            if offset > Self.offRouteDistance {
                farFixes += 1
            } else {
                farFixes = 0
            }
            let wasOffRoute = state.isOffRoute
            state.isOffRoute = farFixes >= Self.offRouteFixes
            if state.isOffRoute, !wasOffRoute {
                cues.append(.offRoute)
            }

            state.remainingDistance = max((cumulative.last ?? 0) - along, 0)
            if let total = cumulative.last, total > 0 {
                state.remainingTime = route.expectedTravelTime * state.remainingDistance / total
            }
            if let index = route.steps.firstIndex(where: { $0.distanceAlongRoute > along - Self.passedTolerance }) {
                let step = route.steps[index]
                let distance = max(step.distanceAlongRoute - along, 0)
                state.maneuver = step.maneuver
                state.instruction = step.instruction
                state.distanceToManeuver = distance
                state.stepLength = step.distanceAlongRoute - (index > 0 ? route.steps[index - 1].distanceAlongRoute : 0)
                if step.maneuver != .arrive, !state.isOffRoute {
                    if distance <= Self.turnDistance, turnedSteps.insert(index).inserted {
                        preparedSteps.insert(index)
                        cues.append(.turn(step.maneuver))
                    } else if distance <= Self.prepareDistance, preparedSteps.insert(index).inserted {
                        cues.append(.prepare(step.maneuver))
                    }
                }
            }
        }

        if toDestination <= Self.arrivalRadius {
            state.hasArrived = true
            state.maneuver = .arrive
            state.distanceToManeuver = 0
            state.remainingDistance = 0
            state.remainingTime = state.remainingTime.map { _ in 0 }
            cues.append(.arrived)
        }
        return cues
    }

    /// Plans the rest of the trip without the next stop: from `position`, through the stops after it.
    /// `nil` when no stop is left to skip.
    func routeSkippingNextStop(from position: Coordinate?) async throws -> NavigationRoute? {
        let remaining = remainingStops
        guard !remaining.isEmpty else { return nil }
        // Apple Maps refuses now and then for a moment: a skip that silently does nothing is worse than a wait.
        var attempt = 1
        while true {
            do {
                return try await RoutePlanner.route(
                    to: route.destination,
                    named: route.destinationName,
                    via: Array(remaining.dropFirst()),
                    from: position,
                    avoidsTolls: route.avoidsTolls
                )
            } catch where attempt < 3 {
                attempt += 1
                try await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// The stops not reached yet, for planning a new route that still goes through them.
    var remainingStops: [Waypoint] {
        let along = (cumulative.last ?? 0) - state.remainingDistance
        return route.stops.filter { $0.distanceAlongRoute > along + Self.arrivalRadius }.map(\.waypoint)
    }

    /// Distance along the route of the closest point, and how far the rider is from it.
    ///
    /// Searches near the last known position first, so a route that loops back on itself does not make the
    /// rider jump ahead; the whole route is searched only when nothing nearby matches.
    private mutating func locate(_ position: Coordinate) -> (along: Double, offset: Double) {
        let window = max(segmentIndex - 2, 0)...min(segmentIndex + 200, route.points.count - 2)
        var best = closest(position, in: window)
        if best.offset > Self.offRouteDistance {
            let everywhere = closest(position, in: 0...(route.points.count - 2))
            if everywhere.offset < best.offset {
                best = everywhere
            }
        }
        segmentIndex = best.segment
        return (best.along, best.offset)
    }

    private func closest(_ position: Coordinate, in segments: ClosedRange<Int>) -> (segment: Int, along: Double, offset: Double) {
        var best = (segment: segments.lowerBound, along: 0.0, offset: Double.infinity)
        for segment in segments {
            let (fraction, offset) = Geo.project(position, ontoSegment: route.points[segment], route.points[segment + 1])
            if offset < best.offset {
                let length = cumulative[segment + 1] - cumulative[segment]
                best = (segment, cumulative[segment] + fraction * length, offset)
            }
        }
        return best
    }
}
