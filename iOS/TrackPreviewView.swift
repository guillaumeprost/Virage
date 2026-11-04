import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// Loads a GPX file picked in Files or opened from another app.
enum GPXImport {
    static func load(_ url: URL) throws -> ImportedTrack {
        // Files picked in place belong to another app's sandbox until access is asked for.
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        return try GPXReader.read(data, fallbackName: url.deletingPathExtension().lastPathComponent)
    }
}

/// The imported line on the map, laid out like the route preview: follow it as planned, either way round.
struct TrackPreviewView: View {
    let track: ImportedTrack
    let onStart: () -> Void

    @Environment(RideEngine.self) private var engine
    @Environment(NavigationController.self) private var navigation
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @State private var isReversed = false
    @State private var camera: MapCameraPosition = .automatic

    private var current: ImportedTrack {
        isReversed ? track.reversed : track
    }

    private var route: NavigationRoute? {
        RouteBuilder.follow(current)
    }

    var body: some View {
        let route = route
        Map(position: $camera) {
            if let route {
                MapPolyline(coordinates: route.points.map(\.clLocation))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let start = current.points.first {
                Marker("Départ", systemImage: "flag", coordinate: start.clLocation)
                    .tint(.green)
            }
            if let end = current.points.last {
                Marker(track.name, systemImage: "flag.checkered", coordinate: end.clLocation)
                    .tint(.red)
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
        }
        .safeAreaInset(edge: .bottom) {
            panel(route)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fit)
    }

    private func panel(_ route: NavigationRoute?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Trace GPX, suivie telle quelle", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let route {
                HStack(alignment: .firstTextBaseline) {
                    Text("≈ " + Duration.seconds(route.expectedTravelTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .font(.title2.weight(.bold))
                    Text("\(Format.distance(route.distance, unit)) · \(route.steps.count - 1) virages annoncés")
                        .foregroundStyle(.secondary)
                }
                if let position = engine.snapshot.position, let start = route.points.first, Geo.distance(position, start) > 300 {
                    Label("Départ à \(Format.distance(Geo.distance(position, start), unit)) : rejoins la trace", systemImage: "location")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Parcourir en sens inverse", isOn: $isReversed)

            Button {
                guard let route else { return }
                navigation.start(route, from: engine.snapshot.position)
                engine.startRide()
                onStart()
            } label: {
                Label("Suivre la trace", systemImage: "location.north.line.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(route == nil)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func fit() {
        var coordinates = track.points.map(\.clLocation)
        guard !coordinates.isEmpty else { return }
        let bounds = MKPolyline(coordinates: &coordinates, count: coordinates.count).boundingMapRect
        camera = .rect(bounds.insetBy(dx: -bounds.width * 0.15, dy: -bounds.height * 0.15))
    }
}
