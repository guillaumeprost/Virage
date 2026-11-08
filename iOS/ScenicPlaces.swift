import MapKit
import SwiftUI

/// Where a place sits relative to the route being followed: shared by fuel stations and scenic places.
enum AlongRoute {
    static func cumulative(_ points: [Coordinate]) -> [Double] {
        var cumulative = [0.0]
        for index in points.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + Geo.distance(points[index - 1], points[index]))
        }
        return cumulative
    }

    /// The rider's position, then points the given distances further along the route.
    static func centers(from position: Coordinate, route: NavigationRoute?, riddenAlong: Double, ahead offsets: [Double]) -> [Coordinate] {
        var centers = [position]
        guard let route, route.mode == .route, !route.points.isEmpty else { return centers }
        let cumulative = cumulative(route.points)
        for offset in offsets {
            let target = riddenAlong + offset
            guard target < (cumulative.last ?? 0), let index = cumulative.firstIndex(where: { $0 >= target }) else { continue }
            centers.append(route.points[index])
        }
        return centers
    }

    /// How far ahead along the route the place's closest point is, and how far off the route it sits.
    static func placement(of coordinate: Coordinate, on points: [Coordinate], cumulative: [Double], riddenAlong: Double) -> (ahead: Double, offRoute: Double)? {
        guard !points.isEmpty else { return nil }
        var best = (index: 0, distance: Double.infinity)
        for (index, point) in points.enumerated() {
            let distance = Geo.distance(point, coordinate)
            if distance < best.distance {
                best = (index, distance)
            }
        }
        return (cumulative[best.index] - riddenAlong, best.distance)
    }

    static func coordinate(of item: MKMapItem) -> Coordinate {
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        return Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// A mountain pass or a viewpoint worth a stop.
struct ScenicPlace: Identifiable, Hashable {
    enum Kind {
        case pass
        case viewpoint

        var systemImage: String {
            switch self {
            case .pass: "mountain.2.fill"
            case .viewpoint: "binoculars.fill"
            }
        }
    }

    var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }
    var name: String
    var kind: Kind
    var coordinate: Coordinate
    /// As the crow flies from the rider, in meters.
    var distance: Double
    var ahead: Double?
    var offRoute: Double?

    var isOnTheWay: Bool {
        guard let ahead, let offRoute else { return false }
        return ahead >= 0 && offRoute <= ScenicSearch.onTheWayDistance
    }
}

enum ScenicSearch {
    /// A pass or viewpoint this far off the route is still worth the detour on a ride.
    static let onTheWayDistance = 3_000.0
    static let lookAhead: [Double] = [10_000, 25_000, 45_000]
    static let searchRadius = 10_000.0
    /// A pass is crossed when the track comes this close to it.
    static let crossingDistance = 200.0
    /// Along a recorded track, a small search every this many meters: Maps returns only a couple of dozen places
    /// per search, so a wide one misses passes a narrow one finds.
    static let trackSampling = 6_000.0
    static let trackSearchRadius = 5_000.0
    /// Two queries each: within what Apple Maps allows in a minute.
    static let maximumTrackSearches = 20

    /// Names say what Apple Maps does not: passes and viewpoints have no category of their own.
    static func kind(of name: String) -> ScenicPlace.Kind? {
        var name = name.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        // "Le Col de la Forclaz": the article first.
        for article in ["le ", "la ", "l'", "l’"] where name.hasPrefix(article) {
            name.removeFirst(article.count)
        }
        let passPrefixes = ["col ", "col d", "pas de ", "passo ", "colle ", "puerto de", "port de "]
        if passPrefixes.contains(where: name.hasPrefix) || name.hasSuffix(" pass") || name.contains("pass ") {
            return .pass
        }
        let viewpointWords = ["point de vue", "belvedere", "panorama", "viewpoint", "table d'orientation"]
        if viewpointWords.contains(where: name.contains) {
            return .viewpoint
        }
        return nil
    }

    /// Around the rider and further along the route: on the way first, the nearest ahead leading.
    static func places(near position: Coordinate, route: NavigationRoute?, riddenAlong: Double) async -> [ScenicPlace] {
        let centers = AlongRoute.centers(from: position, route: route, riddenAlong: riddenAlong, ahead: lookAhead)
        let found = await search(around: centers, queries: ["col", "point de vue", "belvédère"], radius: searchRadius, concurrently: true)
        let points = route?.mode == .route ? route?.points ?? [] : []
        let cumulative = AlongRoute.cumulative(points)
        let places = found.map { name, kind, coordinate in
            var place = ScenicPlace(name: name, kind: kind, coordinate: coordinate, distance: Geo.distance(position, coordinate))
            if let placement = AlongRoute.placement(of: coordinate, on: points, cumulative: cumulative, riddenAlong: riddenAlong) {
                place.ahead = placement.ahead
                place.offRoute = placement.offRoute
            }
            return place
        }
        let onTheWay = places.filter(\.isOnTheWay).sorted { ($0.ahead ?? 0) < ($1.ahead ?? 0) }
        let others = places.filter { !$0.isOnTheWay }.sorted { $0.distance < $1.distance }
        let ordered = onTheWay + others
        // Each kind its share: the many passes of a mountain must not push every viewpoint off the list.
        return Array(ordered.filter { $0.kind == .pass }.prefix(10)) + Array(ordered.filter { $0.kind == .viewpoint }.prefix(8))
    }

    /// The passes a recorded track goes over, in the order it crossed them.
    static func passes(along track: [Coordinate]) async -> [TripPass] {
        guard track.count >= 2 else { return [] }
        let cumulative = AlongRoute.cumulative(track)
        var centers: [Coordinate] = []
        var next = 0.0
        for (index, distance) in cumulative.enumerated() where distance >= next {
            centers.append(track[index])
            next = distance + trackSampling
        }
        centers.append(track[track.count - 1])
        // Apple Maps limits the rate: on a long ride, the searches spread evenly over the whole track.
        if centers.count > maximumTrackSearches {
            let step = Double(centers.count - 1) / Double(maximumTrackSearches - 1)
            centers = (0..<maximumTrackSearches).map { centers[Int((Double($0) * step).rounded())] }
        }
        // "Le Col de la Forclaz" only comes up when asked with its article.
        let found = await search(around: centers, queries: ["col", "le col"], radius: trackSearchRadius)
        let crossed = found.compactMap { name, kind, coordinate -> (TripPass, Double)? in
            guard kind == .pass,
                  let placement = AlongRoute.placement(of: coordinate, on: track, cumulative: cumulative, riddenAlong: 0),
                  placement.offRoute <= crossingDistance else { return nil }
            return (TripPass(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude), placement.ahead)
        }
        return crossings(crossed)
    }

    /// The passes in the order they were crossed; a pass and a place named after it at the same spot are one crossing.
    static func crossings(_ crossed: [(pass: TripPass, along: Double)]) -> [TripPass] {
        var passes: [TripPass] = []
        for (pass, _) in crossed.sorted(by: { $0.along < $1.along }) {
            if passes.allSatisfy({ Geo.distance($0.position, pass.position) > 500 }) {
                passes.append(pass)
            }
        }
        return passes
    }

    /// Every query around every center, without duplicates. A handful at once while riding, where the rider waits;
    /// one after another along a whole track, which asks Apple Maps far more often than its rate allows at once.
    private static func search(
        around centers: [Coordinate],
        queries: [String],
        radius: Double,
        concurrently: Bool = false
    ) async -> [(String, ScenicPlace.Kind, Coordinate)] {
        let requests = centers.flatMap { center in queries.map { (center, $0) } }
        var results: [[(String, ScenicPlace.Kind, Coordinate)]] = []
        if concurrently {
            await withTaskGroup(of: [(String, ScenicPlace.Kind, Coordinate)].self) { group in
                for (center, query) in requests {
                    group.addTask { await places(matching: query, around: center, radius: radius) }
                }
                for await found in group {
                    results.append(found)
                }
            }
        } else {
            for (center, query) in requests {
                results.append(await places(matching: query, around: center, radius: radius))
            }
        }
        return deduplicated(Array(results.joined()))
    }

    /// One pin per place, but two passes may share a name (there are several cols de la Forclaz): keyed by name
    /// and rough position, about 2 km.
    static func deduplicated(_ places: [(String, ScenicPlace.Kind, Coordinate)]) -> [(String, ScenicPlace.Kind, Coordinate)] {
        var found: [String: (String, ScenicPlace.Kind, Coordinate)] = [:]
        var order: [String] = []
        for place in places {
            let (name, _, coordinate) = place
            let key = "\(name)|\(Int(coordinate.latitude * 50))|\(Int(coordinate.longitude * 50))"
            if found[key] == nil {
                found[key] = place
                order.append(key)
            }
        }
        return order.compactMap { found[$0] }
    }

    /// Maps writes many passes in lower case ("col de Bluffy"), some with an article ("Le Col de la Forclaz"): both
    /// read "Col de …".
    static func displayName(_ rawName: String, kind: ScenicPlace.Kind) -> String {
        var trimmed = Substring(rawName)
        for article in ["Le ", "La ", "le ", "la "] where trimmed.hasPrefix(article) && kind == .pass {
            trimmed = trimmed.dropFirst(article.count)
        }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    private static func places(matching query: String, around center: Coordinate, radius: Double) async -> [(String, ScenicPlace.Kind, Coordinate)] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .physicalFeature]
        request.region = MKCoordinateRegion(center: center.clLocation, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        return items.compactMap { item in
            guard let rawName = item.name, let kind = kind(of: rawName) else { return nil }
            return (displayName(rawName, kind: kind), kind, AlongRoute.coordinate(of: item))
        }
    }
}

/// Heading somewhere chosen on the way: a stop on the route being followed, or a route of its own.
@MainActor
enum Detour {
    static func go(to stop: Waypoint, navigation: NavigationController, engine: RideEngine) async throws {
        if navigation.acceptsStops {
            try await navigation.insertStop(stop)
        } else {
            let route = try await RoutePlanner.route(to: stop.coordinate, named: stop.name, from: engine.snapshot.position, options: RouteOptions())
            navigation.start(route, from: engine.snapshot.position)
            engine.startRide()
        }
    }
}

/// Passes and viewpoints around and ahead: a tap makes one the next stop.
struct ScenicSheet: View {
    @Environment(RideEngine.self) private var engine
    @Environment(NavigationController.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @State private var places: [ScenicPlace]?
    @State private var going: ScenicPlace?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                if let places {
                    if places.isEmpty {
                        Text("Aucun col ni point de vue trouvé dans les environs.")
                            .foregroundStyle(.secondary)
                    }
                    let viewpoints = places.filter { $0.kind == .viewpoint }
                    section("Cols", places.filter { $0.kind == .pass }, showsFooter: viewpoints.isEmpty)
                    section("Points de vue", viewpoints, showsFooter: true)
                } else {
                    ProgressView("Recherche des cols et points de vue…")
                }
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Cols et points de vue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ places: [ScenicPlace], showsFooter: Bool) -> some View {
        if !places.isEmpty {
            Section {
                ForEach(places) { place in
                    Button {
                        Task { await go(to: place) }
                    } label: {
                        row(place)
                    }
                    .disabled(going != nil)
                }
            } header: {
                Text(title)
            } footer: {
                if showsFooter {
                    Text(navigation.acceptsStops ? "Un lieu choisi devient la prochaine étape de l'itinéraire." : "Un lieu choisi lance le guidage jusqu'à lui.")
                }
            }
        }
    }

    private func row(_ place: ScenicPlace) -> some View {
        HStack {
            Image(systemName: place.kind.systemImage)
                .foregroundStyle(place.isOnTheWay ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(place.name)
                    .foregroundStyle(Color.primary)
                Text(caption(place))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            if going == place {
                ProgressView()
            }
        }
        .frame(minHeight: 44)
    }

    private func caption(_ place: ScenicPlace) -> String {
        if place.isOnTheWay, let ahead = place.ahead, let offRoute = place.offRoute {
            let detour = offRoute < 200 ? "sur la route" : "à \(Format.distance(offRoute, unit)) de la route"
            return "Dans \(Format.distance(ahead, unit)), \(detour)"
        }
        return "À \(Format.distance(place.distance, unit)) à vol d'oiseau"
    }

    private func load() async {
        guard let position = engine.snapshot.position else {
            places = []
            return
        }
        let route = navigation.guidance?.route
        let ridden = navigation.state.map { (route?.distance ?? 0) - $0.remainingDistance } ?? 0
        places = await ScenicSearch.places(near: position, route: route, riddenAlong: ridden)
    }

    private func go(to place: ScenicPlace) async {
        going = place
        failure = nil
        defer { going = nil }
        do {
            try await Detour.go(to: Waypoint(name: place.name, coordinate: place.coordinate), navigation: navigation, engine: engine)
            dismiss()
        } catch {
            failure = RoutePlanner.explain(error)
        }
    }
}

/// A round capsule with a mountain: opens the passes and viewpoints. Styled like the fuel badge.
struct ScenicBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mountain.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background { DashboardCapsule(isAlert: false) }
                .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cols et points de vue")
    }
}

/// The background of the dashboard's small badges: frosted in Classique, a hairline in Retro and Sport, red when
/// it warns.
struct DashboardCapsule: View {
    let isAlert: Bool
    @Environment(\.dashboardStyle) private var style

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .sport ? 8 : 22)
        if isAlert {
            shape.fill(.red)
        } else if style == .classic {
            shape.fill(.regularMaterial)
        } else {
            shape.fill(style.background).strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
        }
    }
}
