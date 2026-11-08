import AppIntents
import SwiftData
import SwiftUI

@main
struct VirageApp: App {
    private let container: ModelContainer
    @State private var connectivity: PhoneConnectivity
    @State private var navigation: NavigationController
    @State private var engine: RideEngine
    @State private var music = NowPlaying()

    init() {
        do {
            container = try ModelContainer(for: Trip.self, RecentDestination.self, FavoritePlace.self, SavedTrack.self)
        } catch {
            fatalError("Cannot open the trip store: \(error)")
        }
        let connectivity = PhoneConnectivity()
        let navigation = NavigationController(connectivity: connectivity)
        _connectivity = State(initialValue: connectivity)
        _navigation = State(initialValue: navigation)
        let engine = RideEngine(modelContainer: container, connectivity: connectivity, navigation: navigation)
        _engine = State(initialValue: engine)
        // For the Action button and Siri, which act on the ride in progress.
        AppDependencyManager.shared.add(dependency: engine)
        AppDependencyManager.shared.add(dependency: navigation)
        connectivity.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(connectivity)
                .environment(navigation)
                .environment(music)
                .task { music.start() }
        }
        .modelContainer(container)
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    /// `nil` follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct RootView: View {
    @Environment(RideEngine.self) private var engine
    @Environment(PhoneConnectivity.self) private var connectivity
    @Environment(NowPlaying.self) private var music
    @Query private var favorites: [FavoritePlace]
    @Query(sort: \RecentDestination.lastUsed, order: .reverse) private var recents: [RecentDestination]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(DashboardStyle.storageKey) private var style = DashboardStyle.classic
    @State private var tab = AppTab.dashboard
    @State private var searchQuery = ""
    @State private var openedDemoPreview = false
    @State private var openedTrack: ImportedTrack?
    @State private var openFailed = false

    enum AppTab: Hashable {
        case dashboard, trips, settings, search
    }

    var body: some View {
        Group {
            // During a ride the dashboard stays where it is and the tabs go away: the whole screen for the ride,
            // without a new page sliding in. Hiding only the tab bar was ignored by the system once it showed.
            if engine.snapshot.isRiding {
                DashboardView()
            } else {
                tabs
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .tint(style.tint)
        .environment(\.dashboardStyle, style)
        // A .gpx file opened from Files, Mail or AirDrop: shown in the search tab, ready to follow.
        .onOpenURL(perform: open)
        .alert("Fichier GPX illisible", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        }
        // The Watch offers the same places, even out of reach of the iPhone.
        .onChange(of: watchPlaces, initial: true) {
            connectivity.send(places: watchPlaces)
        }
        .onChange(of: scenePhase, initial: true) {
            engine.setForeground(scenePhase != .background)
            if scenePhase == .active {
                music.refresh()
            }
        }
        #if DEBUG
        .task { await startDemoNavigation() }
        .task { DemoTrips.insert(into: modelContext) }
        .task {
            // `-demoGPX /path/to/file.gpx`, for trying an import in the simulator without Files.
            if let path = UserDefaults.standard.string(forKey: "demoGPX") {
                open(URL(fileURLWithPath: path))
            }
        }
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Compteur", systemImage: "gauge.with.dots.needle.67percent", value: .dashboard) {
                DashboardView()
            }
            Tab("Trajets", systemImage: "map", value: .trips) {
                TripsListView()
            }
            Tab("Réglages", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
            // The system search tab: set apart in the tab bar, with the search field built in.
            Tab("Rechercher", systemImage: "magnifyingglass", value: .search, role: .search) {
                DestinationSearchView(initialDestination: Self.demoPreview, query: $searchQuery, importedTrack: $openedTrack) {
                    tab = .dashboard
                }
            }
        }
        #if DEBUG
        .onAppear {
            // Once only: the tabs come back after each ride.
            if Self.demoPreview != nil, !openedDemoPreview {
                openedDemoPreview = true
                tab = .search
            }
        }
        #endif
    }

    private func open(_ url: URL) {
        guard !engine.snapshot.isRiding else { return }
        do {
            openedTrack = try GPXImport.load(url)
            tab = .search
        } catch {
            openFailed = true
        }
    }

    /// Favorites first, home and work leading, then the recent destinations not already among them.
    private var watchPlaces: [SavedPlace] {
        let saved = FavoritePlace.sorted(favorites).map { favorite in
            let kind: SavedPlace.Kind = switch favorite.kind {
            case .home: .home
            case .work: .work
            case .other: .favorite
            }
            return SavedPlace(kind: kind, name: favorite.name, subtitle: favorite.subtitle, coordinate: favorite.destination.coordinate)
        }
        let recent = recents.prefix(10)
            .filter { recent in !favorites.contains { $0.isSamePlace(as: recent.destination) } }
            .map { SavedPlace(kind: .recent, name: $0.name, subtitle: $0.subtitle, coordinate: $0.destination.coordinate) }
        return saved + recent
    }

    /// Opens the route preview at launch, for testing it in the simulator without typing:
    /// `-demoPreview "45.8406,6.2131,Talloires"`.
    private static var demoPreview: Destination? {
        #if DEBUG
        guard let argument = UserDefaults.standard.string(forKey: "demoPreview") else { return nil }
        let parts = argument.split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count == 3, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return nil }
        return Destination(name: parts[2], coordinate: Coordinate(latitude: latitude, longitude: longitude))
        #else
        return nil
        #endif
    }

    #if DEBUG
    @Environment(NavigationController.self) private var navigation
    @Environment(\.modelContext) private var modelContext

    /// Starts navigating at launch, for testing in the simulator without typing a destination:
    /// `-demoDestination "45.8406,6.2131,Talloires"`, with `-demoMode compass` for the compass.
    private func startDemoNavigation() async {
        let defaults = UserDefaults.standard
        guard let argument = defaults.string(forKey: "demoDestination") else { return }
        let parts = argument.split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count == 3, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return }
        let destination = Coordinate(latitude: latitude, longitude: longitude)
        let route: NavigationRoute
        if defaults.string(forKey: "demoMode") == NavigationMode.compass.rawValue {
            route = RoutePlanner.compass(to: destination, named: parts[2])
        } else {
            // Wait for a first fix, since the route starts from the current location.
            while engine.snapshot.position == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            // Apple Maps sometimes refuses a route for a moment; a demo should not need a relaunch for that.
            var planned: NavigationRoute?
            for _ in 1...5 where planned == nil {
                planned = try? await RoutePlanner.route(to: destination, named: parts[2], options: RouteOptions())
                if planned == nil {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            guard let planned else { return }
            route = planned
        }
        navigation.start(route, from: engine.snapshot.position)
        engine.startRide()
    }
    #endif
}
