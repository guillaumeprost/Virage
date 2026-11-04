import Foundation

/// A route or a track read from a GPX file, as planned in a ride planner.
struct ImportedTrack: Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var points: [Coordinate]

    var reversed: ImportedTrack {
        ImportedTrack(id: id, name: name, points: points.reversed())
    }
}

enum GPXReader {
    enum Failure: Error {
        case unreadable
        case noPoints
    }

    /// The planned route if the file has one (`rtept`), otherwise the recorded track (`trkpt`), otherwise the
    /// waypoints in order (`wpt`).
    static func read(_ data: Data, fallbackName: String) throws -> ImportedTrack {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() else { throw Failure.unreadable }
        let points = [collector.routePoints, collector.trackPoints, collector.waypoints].first { $0.count >= 2 } ?? []
        guard !points.isEmpty else { throw Failure.noPoints }
        let name = collector.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedTrack(name: name?.isEmpty == false ? name! : fallbackName, points: points)
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var routePoints: [Coordinate] = []
        var trackPoints: [Coordinate] = []
        var waypoints: [Coordinate] = []
        var name: String?
        private var path: [String] = []
        private var text = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            // Namespaces are written with prefixes in some files ("gpx:trkpt").
            let element = elementName.split(separator: ":").last.map(String.init) ?? elementName
            path.append(element)
            text = ""
            guard ["rtept", "trkpt", "wpt"].contains(element),
                  let latitude = attributes["lat"].flatMap(Double.init),
                  let longitude = attributes["lon"].flatMap(Double.init) else { return }
            let point = Coordinate(latitude: latitude, longitude: longitude)
            switch element {
            case "rtept": routePoints.append(point)
            case "trkpt": trackPoints.append(point)
            default: waypoints.append(point)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            // The name of the route or track, else of the file: not that of a single point.
            if path.last == "name", name == nil, path.count >= 2, ["rte", "trk", "metadata"].contains(path[path.count - 2]) {
                name = text
            }
            path.removeLast()
        }
    }
}

extension RouteBuilder {
    /// A turn sharper than this along a track is announced.
    static let trackTurnAngle = 45.0
    /// Two turns closer than this along a track are one bend: only the sharpest is announced.
    static let trackTurnSpacing = 60.0
    /// For the time estimate: a winding road, ridden at a steady pace.
    static let trackAverageSpeed = 15.0

    /// A route that follows the GPX line itself, rather than one Apple Maps would choose. A track has no road
    /// names: the turns are read from its shape, and announced by their direction alone.
    static func follow(_ track: ImportedTrack) -> NavigationRoute? {
        // Points a few meters apart only add GPS noise to the turn measurements.
        var points: [Coordinate] = []
        for point in track.points where points.last.map({ Geo.distance($0, point) >= 5 }) ?? true {
            points.append(point)
        }
        guard points.count >= 2, let destination = points.last else { return nil }

        var cumulative = [0.0]
        for index in points.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + Geo.distance(points[index - 1], points[index]))
        }
        let total = cumulative.last ?? 0

        var turns: [(index: Int, angle: Double)] = []
        for index in points.indices.dropFirst().dropLast() {
            let angle = turnAngle(at: index, points: points, cumulative: cumulative)
            guard abs(angle) >= trackTurnAngle else { continue }
            if let last = turns.last, cumulative[index] - cumulative[last.index] < trackTurnSpacing {
                if abs(angle) > abs(last.angle) {
                    turns[turns.count - 1] = (index, angle)
                }
            } else {
                turns.append((index, angle))
            }
        }

        var steps = turns.map { turn in
            let maneuver = Maneuver.from(turnAngle: turn.angle)
            return RouteStep(instruction: maneuver.trackInstruction, maneuver: maneuver, distanceAlongRoute: cumulative[turn.index])
        }
        steps.append(RouteStep(instruction: track.name, maneuver: .arrive, distanceAlongRoute: total))

        return NavigationRoute(
            destinationName: track.name,
            destination: destination,
            mode: .route,
            avoidsTolls: false,
            points: points,
            steps: steps,
            distance: total,
            expectedTravelTime: total / trackAverageSpeed,
            followsTrack: true
        )
    }
}

extension Maneuver {
    /// What to say at a turn found on a track, where there is no road name to give.
    var trackInstruction: String {
        switch self {
        case .straight: "Continuez tout droit"
        case .slightLeft: "Prenez légèrement à gauche"
        case .left: "Tournez à gauche"
        case .sharpLeft: "Virage serré à gauche"
        case .slightRight: "Prenez légèrement à droite"
        case .right: "Tournez à droite"
        case .sharpRight: "Virage serré à droite"
        case .uTurn: "Épingle"
        case .waypoint: "Étape"
        case .arrive: "Arrivée"
        }
    }
}
