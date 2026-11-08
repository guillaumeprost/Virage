import MapKit
import SwiftUI

/// The route and the rider's position, oriented in the direction of travel.
///
/// Equatable on the route and the position only: the dashboard redraws 25 times a second for the lean angle,
/// and rebuilding a route of thousands of points each time would be wasted work.
struct RideMapView: View, Equatable {
    let route: NavigationRoute
    let position: Coordinate?
    /// Off where the map sits inside a scrolling view, so a drag scrolls instead of panning the map.
    var isInteractive = true
    /// When set, the map shows no controls of its own: the screen places them, bound to this scope, where they
    /// stay clear of what floats over the map.
    var controlsScope: Namespace.ID?

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    nonisolated static func == (lhs: RideMapView, rhs: RideMapView) -> Bool {
        lhs.route.id == rhs.route.id && lhs.position == rhs.position && lhs.isInteractive == rhs.isInteractive
            && lhs.controlsScope == rhs.controlsScope
    }

    var body: some View {
        let destination = CLLocationCoordinate2D(latitude: route.destination.latitude, longitude: route.destination.longitude)
        Map(position: $camera, interactionModes: isInteractive ? .all : [], scope: controlsScope) {
            if route.mode == .route {
                MapPolyline(coordinates: route.points.map(\.clLocation))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            } else if let position {
                // In compass mode there is no route: a dashed line shows where the destination lies.
                MapPolyline(coordinates: [position.clLocation, destination])
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            }
            ForEach(Array(route.stops.enumerated()), id: \.offset) { _, stop in
                Marker(stop.waypoint.name, systemImage: "mappin", coordinate: stop.waypoint.coordinate.clLocation)
                    .tint(.blue)
            }
            Marker(route.destinationName, systemImage: "flag.checkered", coordinate: destination)
                .tint(.red)
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        #if os(iOS)
        .mapControls {
            if controlsScope == nil {
                MapUserLocationButton()
                MapCompass()
            }
        }
        #endif
    }
}

extension Coordinate {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
