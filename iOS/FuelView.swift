import MapKit
import SwiftUI

/// A fuel station found nearby, placed relative to the rider and to the route being followed.
struct GasStation: Identifiable, Hashable {
    var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }
    var name: String
    var coordinate: Coordinate
    /// As the crow flies from the rider, in meters.
    var distance: Double
    /// How far ahead along the route the closest point is, and how far off the route the station sits.
    var ahead: Double?
    var offRoute: Double?

    /// What reaching it costs on the way: the distance ahead, plus going to it off the route and back.
    var cost: Double {
        (ahead ?? distance) + 2 * (offRoute ?? 0)
    }

    /// Close enough to the route to stop on the way.
    var isOnTheWay: Bool {
        guard let ahead, let offRoute else { return false }
        return ahead >= 0 && offRoute <= GasStationSearch.onTheWayDistance
    }
}

enum GasStationSearch {
    /// Further off the route than this, a station is a detour rather than a stop on the way.
    static let onTheWayDistance = 2_000.0
    /// Where to look along the route, ahead of the rider: what the reserve allows to reach.
    static let lookAhead: [Double] = [0, 15_000, 35_000]
    static let searchRadius = 8_000.0

    /// Stations on the way first, the cheapest to reach leading; then the others, nearest first.
    static func stations(near position: Coordinate, route: NavigationRoute?, riddenAlong: Double) async -> [GasStation] {
        let centers = AlongRoute.centers(from: position, route: route, riddenAlong: riddenAlong, ahead: Array(lookAhead.dropFirst()))

        var found: [String: (name: String, coordinate: Coordinate)] = [:]
        await withTaskGroup(of: [(String, Coordinate)].self) { group in
            for center in centers {
                group.addTask { await search(around: center) }
            }
            for await results in group {
                for (name, coordinate) in results {
                    found["\(name)|\(String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))"] = (name, coordinate)
                }
            }
        }

        let points = route?.mode == .route ? route?.points ?? [] : []
        let cumulative = AlongRoute.cumulative(points)
        let stations = found.values.map { item in
            var station = GasStation(name: item.name, coordinate: item.coordinate, distance: Geo.distance(position, item.coordinate))
            if let placement = AlongRoute.placement(of: item.coordinate, on: points, cumulative: cumulative, riddenAlong: riddenAlong) {
                station.ahead = placement.ahead
                station.offRoute = placement.offRoute
            }
            return station
        }
        let onTheWay = stations.filter(\.isOnTheWay).sorted { $0.cost < $1.cost }
        let others = stations.filter { !$0.isOnTheWay }.sorted { $0.distance < $1.distance }
        return Array((onTheWay + others).prefix(15))
    }

    /// By category and by name together: each finds stations the other misses, the category search often
    /// returning only a few.
    private static func search(around center: Coordinate) async -> [(String, Coordinate)] {
        let filter = MKPointOfInterestFilter(including: [.gasStation])
        let nearby = MKLocalPointsOfInterestRequest(center: center.clLocation, radius: searchRadius)
        nearby.pointOfInterestFilter = filter
        let named = MKLocalSearch.Request()
        named.naturalLanguageQuery = "station-service"
        named.resultTypes = .pointOfInterest
        named.pointOfInterestFilter = filter
        named.region = MKCoordinateRegion(center: center.clLocation, latitudinalMeters: searchRadius * 2, longitudinalMeters: searchRadius * 2)
        let items = (try? await MKLocalSearch(request: nearby).start())?.mapItems ?? []
        let more = (try? await MKLocalSearch(request: named).start())?.mapItems ?? []
        return (items + more).map { item in
            (item.name ?? "Station-service", AlongRoute.coordinate(of: item))
        }
    }
}

/// The tank at a glance: what is left, the fill-up button, and the stations to reach.
struct FuelSheet: View {
    @Environment(RideEngine.self) private var engine
    @Environment(NavigationController.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @State private var stations: [GasStation]?
    @State private var going: GasStation?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if let fuel = engine.fuel {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Format.range(fuel.remaining, unit))
                                    .font(.largeTitle.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(fuel.isLow ? .red : .primary)
                                Text("d'autonomie")
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: fuel.remaining, total: fuel.range)
                                .tint(fuel.isLow ? .red : .blue)
                            Text("\(Format.distance(engine.sinceRefuel, unit)) depuis le plein")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Format.distance(engine.sinceRefuel, unit))
                                    .font(.largeTitle.weight(.bold))
                                    .monospacedDigit()
                                Text("depuis le plein")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        engine.refuel()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "fuelpump.fill")
                            Text("Plein fait")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    if let stations {
                        if stations.isEmpty {
                            Text("Aucune station trouvée dans les environs.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(stations) { station in
                            Button {
                                Task { await go(to: station) }
                            } label: {
                                row(station)
                            }
                            .disabled(going != nil)
                        }
                    } else {
                        ProgressView("Recherche des stations…")
                    }
                    if let failure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Stations-service")
                } footer: {
                    if navigation.acceptsStops {
                        Text("Une station choisie devient la prochaine étape de l'itinéraire.")
                    } else {
                        Text("Une station choisie lance le guidage jusqu'à elle.")
                    }
                }
            }
            .navigationTitle("Carburant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func row(_ station: GasStation) -> some View {
        HStack {
            Image(systemName: "fuelpump.fill")
                .foregroundStyle(station.isOnTheWay ? .blue : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(station.name)
                    .foregroundStyle(Color.primary)
                Text(caption(station))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            if going == station {
                ProgressView()
            }
        }
    }

    private func caption(_ station: GasStation) -> String {
        if station.isOnTheWay, let ahead = station.ahead, let offRoute = station.offRoute {
            let detour = offRoute < 150 ? "sur la route" : "à \(Format.distance(offRoute, unit)) de la route"
            return "Dans \(Format.distance(ahead, unit)), \(detour)"
        }
        return "À \(Format.distance(station.distance, unit)) à vol d'oiseau"
    }

    private func load() async {
        guard let position = engine.snapshot.position else {
            stations = []
            return
        }
        let route = navigation.guidance?.route
        let ridden = navigation.state.map { (route?.distance ?? 0) - $0.remainingDistance } ?? 0
        stations = await GasStationSearch.stations(near: position, route: route, riddenAlong: ridden)
    }

    private func go(to station: GasStation) async {
        going = station
        failure = nil
        defer { going = nil }
        do {
            try await Detour.go(to: Waypoint(name: station.name, coordinate: station.coordinate), navigation: navigation, engine: engine)
            dismiss()
        } catch {
            failure = RoutePlanner.explain(error)
        }
    }
}

/// The tank at a glance, as a small capsule: the range left when it is tracked, otherwise the kilometers since
/// the last fill-up. Tapped, it opens the fuel sheet.
struct FuelBadge: View {
    let sinceRefuel: Double
    let fuel: FuelGauge?
    let action: () -> Void
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @Environment(\.dashboardStyle) private var style

    private var isLow: Bool { fuel?.isLow ?? false }

    var body: some View {
        Button(action: action) {
            Label(text, systemImage: isLow ? "fuelpump.exclamationmark.fill" : "fuelpump.fill")
                .font(style.figureFont(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline))
                .monospacedDigit()
                .styledDigits(style)
                .foregroundStyle(isLow ? .white : .primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background { DashboardCapsule(isAlert: isLow) }
                .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var text: String {
        if let fuel {
            return Format.range(fuel.remaining, unit)
        }
        // A trip counter, read to the tenth like the one on the bike.
        return Format.distance(sinceRefuel, unit)
    }

    private var accessibilityText: String {
        if let fuel {
            return "Carburant : \(Format.range(fuel.remaining, unit)) d'autonomie"
        }
        return "\(Format.distance(sinceRefuel, unit)) depuis le plein"
    }
}
