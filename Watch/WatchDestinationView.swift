import MapKit
import SwiftUI

/// Choosing where to go from the wrist: the iPhone's favorites and recents, or a search by voice or Scribble.
struct WatchDestinationView: View {
    @Environment(WatchRideModel.self) private var model
    /// Called once guidance has started, to close the screen.
    let onStart: () -> Void

    @State private var query = ""
    @State private var results: [SavedPlace] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    var body: some View {
        List {
            Section {
                TextField("Rechercher", text: $query)
                    .onSubmit { Task { await search() } }
            }
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if searchFailed {
                Text("Aucun résultat")
                    .foregroundStyle(.secondary)
            }
            if !results.isEmpty {
                Section("Résultats") {
                    rows(results)
                }
            }
            let favorites = model.places.filter { $0.kind != .recent }
            if !favorites.isEmpty {
                Section("Favoris") {
                    rows(favorites)
                }
            }
            let recents = model.places.filter { $0.kind == .recent }
            if !recents.isEmpty {
                Section("Récents") {
                    rows(recents)
                }
            }
            if model.places.isEmpty, results.isEmpty, !isSearching {
                Text("Tes favoris et tes destinations récentes de l'iPhone s'afficheront ici.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Destination")
    }

    private func rows(_ places: [SavedPlace]) -> some View {
        ForEach(places) { place in
            NavigationLink {
                WatchDestinationConfirmView(place: place, onStart: onStart)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(place.title)
                            .lineLimit(1)
                        if place.kind == .home || place.kind == .work {
                            Text(place.name)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if !place.subtitle.isEmpty {
                            Text(place.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: place.symbol)
                        .foregroundStyle(place.kind == .recent ? Color.secondary : Color.blue)
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        searchFailed = false
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let position = model.snapshot.position {
            // Nearby places first, as in Maps.
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude),
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        results = items.prefix(8).compactMap(SavedPlace.init)
        searchFailed = results.isEmpty
    }
}

private extension SavedPlace {
    init?(_ item: MKMapItem) {
        let coordinate: CLLocationCoordinate2D
        let subtitle: String
        if #available(watchOS 26, *) {
            coordinate = item.location.coordinate
            subtitle = item.addressRepresentations?.cityWithContext ?? ""
        } else {
            coordinate = item.placemark.coordinate
            subtitle = item.placemark.locality ?? ""
        }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        self.init(
            kind: .recent,
            name: item.name ?? "Destination",
            subtitle: subtitle,
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }
}

/// The last step: route or compass, tolls, and go.
private struct WatchDestinationConfirmView: View {
    @Environment(WatchRideModel.self) private var model
    @AppStorage(WatchSettings.avoidsTollsKey) private var avoidsTolls = true
    @AppStorage(WatchSettings.routeStyleKey) private var routeStyle = RouteStyle.fastest
    @State private var mode = NavigationMode.route
    @State private var isPlanning = false
    @State private var failure: String?

    let place: SavedPlace
    let onStart: () -> Void

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.title)
                    .font(.headline)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            Picker("Guidage", selection: $mode) {
                Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond").tag(NavigationMode.route)
                Label("Boussole", systemImage: "safari").tag(NavigationMode.compass)
            }
            if mode == .route {
                Picker("Routes", selection: $routeStyle) {
                    ForEach(RouteStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle("Éviter les péages", isOn: $avoidsTolls)
            }

            Button {
                Task { await start() }
            } label: {
                if isPlanning {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Démarrer", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(isPlanning)
            .listRowBackground(Color.clear)

            if let failure {
                Text("Itinéraire introuvable. Réessaie, ou utilise la boussole.\n\(failure)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Guidage")
    }

    private func start() async {
        isPlanning = true
        failure = nil
        defer { isPlanning = false }
        do {
            try await model.navigate(to: place, mode: mode, options: RouteOptions(style: routeStyle, avoidsTolls: avoidsTolls))
            onStart()
        } catch {
            failure = RoutePlanner.explain(error)
        }
    }
}
