import MapKit
import OSLog
import SwiftData
import SwiftUI

/// Apple Maps autocompletion for the destination field.
@MainActor
@Observable
final class DestinationSearch: NSObject {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, near position: Coordinate?) {
        if let position {
            completer.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude),
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }
        completer.queryFragment = query
        if query.isEmpty {
            results = []
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> (name: String, coordinate: Coordinate)? {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else { return nil }
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        return (item.name ?? completion.title, Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

extension DestinationSearch: MKLocalSearchCompleterDelegate {
    // The completer was created on the main thread, so it calls back on the main thread.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            results = self.completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {}
}

struct Destination: Hashable {
    var name: String
    var subtitle = ""
    var coordinate: Coordinate
    /// Stops on the way, as last planned: a recent trip comes back with them.
    var via: [Waypoint] = []
}

/// The content of the search tab: recent destinations, then Apple Maps suggestions as you type.
/// `onStart` leaves the tab once navigation has started.
struct DestinationSearchView: View {
    /// Opened right away when set; only the Debug demo uses it.
    var initialDestination: Destination?
    /// Owned by the tab view, which shows the field: a search tab turns into the field itself.
    @Binding var query: String
    /// A GPX file to preview, picked here or opened from another app.
    @Binding var importedTrack: ImportedTrack?
    let onStart: () -> Void

    @State private var isImporting = false
    @State private var importFailed = false

    @Environment(RideEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecentDestination.lastUsed, order: .reverse) private var recents: [RecentDestination]
    @Query private var favorites: [FavoritePlace]
    @State private var search = DestinationSearch()
    @State private var destination: Destination?
    /// Static: the view is rebuilt after each ride, and the demo must open only once per launch.
    private static var openedInitialDestination = false
    /// The favorite slot being chosen in the place picker.
    @State private var choosingFavorite: FavoritePlace.Kind?

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Favoris") {
                        FavoritesRow(favorites: FavoritePlace.sorted(favorites)) { favorite in
                            destination = favorite.destination
                        } onChoose: { kind in
                            choosingFavorite = kind
                        } onDelete: { favorite in
                            modelContext.delete(favorite)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    if !recents.isEmpty {
                        Section {
                            ForEach(recents) { recent in
                                Button {
                                    destination = recent.destination
                                } label: {
                                    PlaceRow(title: recent.name, subtitle: recent.summary, systemImage: recent.via.isEmpty ? "clock.arrow.circlepath" : "point.topleft.down.to.point.bottomright.curvepath")
                                }
                            }
                            .onDelete { offsets in
                                offsets.map { recents[$0] }.forEach(modelContext.delete)
                            }
                        } header: {
                            HStack {
                                Text("Récents")
                                Spacer()
                                Button("Effacer") {
                                    recents.forEach(modelContext.delete)
                                }
                                .font(.subheadline)
                                .textCase(nil)
                            }
                        }
                    }
                } else {
                    ForEach(search.results, id: \.self) { completion in
                        Button {
                            Task {
                                if let result = try? await search.resolve(completion) {
                                    destination = Destination(
                                        name: result.name,
                                        subtitle: completion.subtitle,
                                        coordinate: result.coordinate
                                    )
                                }
                            }
                        } label: {
                            PlaceRow(title: completion.title, subtitle: completion.subtitle, systemImage: "mappin.circle.fill")
                        }
                    }
                }
            }
            .sheet(item: $choosingFavorite) { kind in
                FavoritePickerView(kind: kind)
            }
            .onChange(of: query) {
                search.update(query: query, near: engine.snapshot.position)
            }
            .navigationTitle("Destination")
            .task {
                // Once only: coming back to the tab must not reopen it.
                if let initialDestination, !Self.openedInitialDestination {
                    Self.openedInitialDestination = true
                    destination = initialDestination
                }
            }
            .navigationDestination(item: $importedTrack) { track in
                TrackPreviewView(track: track) {
                    importedTrack = nil
                    onStart()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importer un GPX", systemImage: "square.and.arrow.down") {
                        isImporting = true
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.gpx, .xml]) { result in
                guard case .success(let url) = result else { return }
                do {
                    importedTrack = try GPXImport.load(url)
                } catch {
                    importFailed = true
                }
            }
            .alert("Fichier GPX illisible", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Il ne contient ni itinéraire ni trace. Exporte-le en GPX depuis ton application de balades.")
            }
            .navigationDestination(item: $destination) { destination in
                RoutePreviewView(destination: destination) { stops in
                    var trip = destination
                    trip.via = stops
                    RecentDestination.record(trip, in: modelContext)
                    // Back to an empty search for next time.
                    self.destination = nil
                    query = ""
                    onStart()
                }
            }
        }
        // Always shown under the title. Left to the system, the field hid at the top of the list, out of reach
        // whenever the list was too short to pull down, as on a fresh install with no recent destinations.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Destination")
    }
}

extension FavoritePlace.Kind: Identifiable {
    var id: Self { self }
}

/// Round buttons in a row, as in Maps: home and work always present (to set when empty), then the other
/// favorites, then an add button. A long press edits or removes one.
private struct FavoritesRow: View {
    let favorites: [FavoritePlace]
    let onOpen: (FavoritePlace) -> Void
    let onChoose: (FavoritePlace.Kind) -> Void
    let onDelete: (FavoritePlace) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach([FavoritePlace.Kind.home, .work], id: \.self) { kind in
                    if let favorite = favorites.first(where: { $0.kind == kind }) {
                        saved(favorite)
                    } else {
                        FavoriteButton(title: kind.title, subtitle: "Ajouter", symbol: kind.symbol, isSet: false) {
                            onChoose(kind)
                        }
                    }
                }
                ForEach(favorites.filter { $0.kind == .other }) { favorite in
                    saved(favorite)
                }
                FavoriteButton(title: "Ajouter", subtitle: "", symbol: "plus", isSet: false) {
                    onChoose(.other)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func saved(_ favorite: FavoritePlace) -> some View {
        FavoriteButton(title: favorite.title, subtitle: favorite.kind == .other ? favorite.subtitle : favorite.name, symbol: favorite.kind.symbol, isSet: true) {
            onOpen(favorite)
        }
        .contextMenu {
            if favorite.kind != .other {
                Button("Modifier", systemImage: "pencil") { onChoose(favorite.kind) }
            }
            Button("Supprimer", systemImage: "trash", role: .destructive) { onDelete(favorite) }
        }
    }
}

private struct FavoriteButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(isSet ? Color.white : Color.accentColor)
                    .frame(width: 56, height: 56)
                    .background(isSet ? Color.accentColor : Color(.secondarySystemFill), in: .circle)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }
}

/// Picks the place for a favorite slot with the same Apple Maps search as the destination field.
private struct FavoritePickerView: View {
    let kind: FavoritePlace.Kind
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        PlacePickerView(title: kind == .other ? "Nouveau favori" : kind.title) { place in
            FavoritePlace.save(place, as: kind, in: modelContext)
        }
    }
}

/// A place found with Apple Maps search, handed to `onPick` before the sheet closes.
private struct PlacePickerView: View {
    let title: String
    let onPick: (Destination) -> Void

    @Environment(RideEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var search = DestinationSearch()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(search.results, id: \.self) { completion in
                Button {
                    Task {
                        guard let result = try? await search.resolve(completion) else { return }
                        onPick(Destination(name: result.name, subtitle: completion.subtitle, coordinate: result.coordinate))
                        dismiss()
                    }
                } label: {
                    PlaceRow(title: completion.title, subtitle: completion.subtitle, systemImage: "mappin.circle.fill")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Adresse ou lieu")
            .onChange(of: query) {
                search.update(query: query, near: engine.snapshot.position)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}

private struct PlaceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                // Plain text colour, as in Maps: a button in a list would otherwise take the accent colour.
                Text(title)
                    .foregroundStyle(Color.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

/// Laid out like route planning in Maps: the map fills the screen and a fixed panel at the bottom holds the
/// choices. Inside a scrolling form, the map caught every drag and the start button could end up out of reach.
struct RoutePreviewView: View {
    let destination: Destination
    /// Called with the stops the trip goes through, for the search history.
    let onStart: ([Waypoint]) -> Void

    @Environment(RideEngine.self) private var engine
    @Environment(NavigationController.self) private var navigation
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @AppStorage("navigationMode") private var mode = NavigationMode.route
    @AppStorage("avoidsTolls") private var avoidsTolls = false
    @State private var route: NavigationRoute?
    @State private var failure: String?
    /// Set when no toll-free route exists and the one shown uses tolls.
    @State private var usesTollsAnyway = false
    @State private var attempt = 0
    /// Places to go through, in order, before the destination.
    @State private var stops: [Destination] = []
    @State private var isAddingStop = false
    @State private var camera: MapCameraPosition = .automatic
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [FavoritePlace]

    private var savedAs: [FavoritePlace] {
        favorites.filter { $0.isSamePlace(as: destination) }
    }

    var body: some View {
        Map(position: $camera) {
            if mode == .route, let route {
                MapPolyline(coordinates: route.points.map(\.clLocation))
                    .stroke(Color.accentColor, lineWidth: 6)
            }
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                Marker(stop.name, monogram: Text("\(index + 1)"), coordinate: stop.coordinate.clLocation)
                    .tint(.blue)
            }
            Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate.clLocation)
                .tint(.red)
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
        }
        .safeAreaInset(edge: .bottom) {
            // A phone's width at most: in landscape the map stays visible beside it, as in Maps.
            panel
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Définir comme Maison", systemImage: FavoritePlace.Kind.home.symbol) {
                    FavoritePlace.save(destination, as: .home, in: modelContext)
                }
                Button("Définir comme Travail", systemImage: FavoritePlace.Kind.work.symbol) {
                    FavoritePlace.save(destination, as: .work, in: modelContext)
                }
                if savedAs.isEmpty {
                    Button("Ajouter aux favoris", systemImage: "star") {
                        FavoritePlace.save(destination, as: .other, in: modelContext)
                    }
                } else {
                    Button("Retirer des favoris", systemImage: "star.slash", role: .destructive) {
                        savedAs.forEach(modelContext.delete)
                    }
                }
            } label: {
                Label("Favori", systemImage: savedAs.isEmpty ? "star" : "star.fill")
            }
        }
        // Fit the whole route once it is known. An explicit rectangle: `.automatic` is already the camera at
        // first, so setting it again changed nothing and the map could stay on the whole world.
        .onChange(of: route?.id) {
            guard let route, !route.points.isEmpty else { return }
            var coordinates = route.points.map(\.clLocation)
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            let bounds = polyline.boundingMapRect
            withAnimation {
                camera = .rect(bounds.insetBy(dx: -bounds.width * 0.15, dy: -bounds.height * 0.15))
            }
        }
        .task(id: "\(avoidsTolls)-\(attempt)-\(stops.map(\.name))") {
            await plan()
        }
        .onAppear {
            // A recent trip comes back with its stops.
            if stops.isEmpty {
                stops = destination.via.map { Destination(name: $0.name, coordinate: $0.coordinate) }
            }
        }
        #if DEBUG
        .onAppear {
            // `-demoStops "45.86,6.19,Menthon;…"`, for trying stops in the simulator without typing.
            guard stops.isEmpty, let argument = UserDefaults.standard.string(forKey: "demoStops") else { return }
            stops = argument.split(separator: ";").compactMap { item in
                let parts = item.split(separator: ",", maxSplits: 2).map(String.init)
                guard parts.count == 3, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return nil }
                return Destination(name: parts[2], coordinate: Coordinate(latitude: latitude, longitude: longitude))
            }
        }
        #endif
        .sheet(isPresented: $isAddingStop) {
            PlacePickerView(title: "Nouvelle étape") { place in
                stops.append(place)
            }
        }
    }

    /// Apple Maps fails now and then for a moment, and some long trips have no toll-free route at all: the
    /// rider gets a route whenever one exists, and the real reason when none does.
    private func plan() async {
        route = nil
        failure = nil
        usesTollsAnyway = false
        // From the known position: on a device just woken, "current location" can take a while to resolve.
        let origin = engine.snapshot.position
        let waypoints = stops.map { Waypoint(name: $0.name, coordinate: $0.coordinate) }
        func attempt(avoidingTolls: Bool) async throws -> NavigationRoute {
            do {
                return try await RoutePlanner.route(to: destination.coordinate, named: destination.name, via: waypoints, from: origin, avoidsTolls: avoidingTolls)
            } catch {
                try await Task.sleep(for: .seconds(1))
                return try await RoutePlanner.route(to: destination.coordinate, named: destination.name, via: waypoints, from: origin, avoidsTolls: avoidingTolls)
            }
        }
        do {
            let planned = try await attempt(avoidingTolls: avoidsTolls)
            // Stops or tolls changed meanwhile: a newer plan is under way, and this one must not overwrite it.
            guard !Task.isCancelled else { return }
            route = planned
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            guard avoidsTolls, let withTolls = try? await attempt(avoidingTolls: false), !Task.isCancelled else {
                guard !Task.isCancelled else { return }
                Logger(subsystem: "com.guillaumeprost.Virage", category: "route").error("No route: \(error, privacy: .public)")
                failure = RoutePlanner.explain(error)
                return
            }
            route = withTolls
            usesTollsAnyway = true
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Mode", selection: $mode) {
                Text("Itinéraire").tag(NavigationMode.route)
                Text("Boussole").tag(NavigationMode.compass)
            }
            .pickerStyle(.segmented)

            if mode == .route {
                stopList
                Toggle("Éviter les péages", isOn: $avoidsTolls)
            }

            summary
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let plan = mode == .route ? route : RoutePlanner.compass(to: destination.coordinate, named: destination.name)
                guard let plan else { return }
                navigation.start(plan, from: engine.snapshot.position)
                engine.startRide()
                onStart(mode == .route ? stops.map { Waypoint(name: $0.name, coordinate: $0.coordinate) } : [])
            } label: {
                Label("Démarrer la navigation", systemImage: "location.north.line.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(mode == .route && route == nil)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// The stops in the order they will be reached, then the button to add one at the end.
    private var stopList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                HStack {
                    Image(systemName: "\(index + 1).circle.fill")
                        .foregroundStyle(.blue)
                    Text(stop.name)
                        .lineLimit(1)
                    Spacer()
                    Button("Retirer l'étape", systemImage: "xmark.circle.fill") {
                        stops.remove(at: index)
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            Button("Ajouter une étape", systemImage: "plus.circle") {
                isAddingStop = true
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        switch mode {
        case .route:
            if let route {
                HStack(alignment: .firstTextBaseline) {
                    Text(Duration.seconds(route.expectedTravelTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .font(.title2.weight(.bold))
                    Text("\(Format.distance(route.distance, unit)) · \(route.steps.count - 1) virages annoncés")
                        .foregroundStyle(.secondary)
                }
                if usesTollsAnyway {
                    Label("Aucun itinéraire sans péage : celui-ci en emprunte.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Itinéraire introuvable", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Réessayer") { attempt += 1 }
                    }
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Calcul de l'itinéraire…")
            }
        case .compass:
            Text(engine.snapshot.position.map {
                "\(Format.distance(Geo.distance($0, destination.coordinate), unit)) à vol d'oiseau · tu choisis tes routes"
            } ?? "Une flèche pointe vers la destination : tu choisis tes routes.")
                .foregroundStyle(.secondary)
        }
    }
}
