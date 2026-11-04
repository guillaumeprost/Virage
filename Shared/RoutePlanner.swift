import MapKit

/// Plans routes with Apple Maps. Runs on the iPhone, and on the Watch when it reroutes on its own.
enum RoutePlanner {
    /// `from` is the current location when `nil`. With stops, each leg is planned on its own, all at once, and
    /// the legs joined in order: MapKit plans from one point to another only.
    static func route(
        to destination: Coordinate,
        named destinationName: String,
        via stops: [Waypoint] = [],
        from origin: Coordinate? = nil,
        avoidsTolls: Bool
    ) async throws -> NavigationRoute {
        guard !stops.isEmpty else {
            return try await leg(to: destination, named: destinationName, from: origin, avoidsTolls: avoidsTolls)
        }
        let ends = stops.map { ($0.coordinate, $0.name) } + [(destination, destinationName)]
        let starts: [Coordinate?] = [origin] + stops.map(\.coordinate)
        let legs = try await withThrowingTaskGroup(of: (Int, NavigationRoute).self) { group in
            for index in ends.indices {
                group.addTask {
                    (index, try await leg(to: ends[index].0, named: ends[index].1, from: starts[index], avoidsTolls: avoidsTolls))
                }
            }
            var legs: [(Int, NavigationRoute)] = []
            for try await leg in group {
                legs.append(leg)
            }
            return legs.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return RouteBuilder.join(legs, stops: stops, destinationName: destinationName, destination: destination, avoidsTolls: avoidsTolls)
    }

    private static func leg(
        to destination: Coordinate,
        named destinationName: String,
        from origin: Coordinate?,
        avoidsTolls: Bool
    ) async throws -> NavigationRoute {
        let request = MKDirections.Request()
        request.source = origin.map(mapItem) ?? .forCurrentLocation()
        request.destination = mapItem(destination)
        // MapKit has no motorcycle profile; driving is the closest.
        request.transportType = .automobile
        request.tollPreference = avoidsTolls ? .avoid : .any
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
        return RouteBuilder.build(
            steps: route.steps.map { ($0.instructions, coordinates(of: $0.polyline)) },
            destinationName: destinationName,
            destination: destination,
            avoidsTolls: avoidsTolls,
            expectedTravelTime: route.expectedTravelTime
        )
    }

    /// Why Apple Maps gave no route, in words a rider can act on, with the code for a bug report.
    static func explain(_ error: any Error) -> String {
        let error = error as NSError
        let reason: String
        if error.domain == MKErrorDomain, let code = MKError.Code(rawValue: UInt(error.code)) {
            reason = switch code {
            case .directionsNotFound: "Apple Plans ne trouve pas de route jusqu'à ce point."
            case .loadingThrottled: "Trop de demandes à Apple Plans : réessaie dans une minute."
            case .serverFailure: "Apple Plans ne répond pas pour le moment."
            case .placemarkNotFound: "Destination introuvable sur la carte."
            default: "Apple Plans n'a pas pu calculer l'itinéraire."
            }
        } else if error.domain == NSURLErrorDomain {
            reason = "Pas de connexion à Internet."
        } else {
            reason = "Apple Plans n'a pas pu calculer l'itinéraire."
        }
        return "\(reason) (\(error.domain) \(error.code))"
    }

    static func compass(to destination: Coordinate, named destinationName: String) -> NavigationRoute {
        NavigationRoute(destinationName: destinationName, destination: destination, mode: .compass, avoidsTolls: false)
    }

    static func mapItem(_ coordinate: Coordinate) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26, watchOS 26, *) {
            return MKMapItem(location: location, address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
    }

    private static func coordinates(of polyline: MKPolyline) -> [Coordinate] {
        var raw = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&raw, range: NSRange(location: 0, length: polyline.pointCount))
        return raw.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
