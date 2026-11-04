import MapKit
import SwiftData
import SwiftUI

struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour

    var body: some View {
        NavigationStack {
            List {
                ForEach(trips) { trip in
                    NavigationLink(value: trip) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text("\(Format.distance(trip.distance, unit)) · \(Format.duration(trip.movingTime)) · max \(Format.speed(trip.maxSpeed, unit)) \(unit.speedLabel)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { trips[$0] }.forEach(modelContext.delete)
                }
            }
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "Aucun trajet",
                        systemImage: "road.lanes",
                        description: Text("Démarre un trajet depuis le compteur ou depuis ta montre.")
                    )
                }
            }
            .navigationTitle("Trajets")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
        }
    }
}

/// Same layout as the route preview: the map fills the screen, the figures sit in a panel at the bottom.
struct TripDetailView: View {
    let trip: Trip
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour

    var body: some View {
        let track = trip.track
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: track.map(\.coordinate))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            if let first = track.first {
                Marker("Départ", systemImage: "flag", coordinate: first.coordinate).tint(.green)
            }
            if let last = track.last {
                Marker("Arrivée", systemImage: "flag.checkered", coordinate: last.coordinate).tint(.red)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            summary
        }
        .navigationTitle(trip.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: GPXFile(trip: trip), preview: SharePreview("Trajet GPX")) {
                Label("Exporter en GPX", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.distance(trip.distance, unit))
                    .font(.title2.weight(.bold))
                Text(Duration.seconds(trip.movingTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(trip.startDate.formatted(date: .omitted, time: .shortened) + " – " + trip.endDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()

            HStack(alignment: .top) {
                figure("Moyenne", "\(Format.speed(trip.averageSpeed, unit)) \(unit.speedLabel)")
                figure("Max", "\(Format.speed(trip.maxSpeed, unit)) \(unit.speedLabel)")
                figure("Incl. G", Format.lean(trip.maxLeanLeft))
                figure("Incl. D", Format.lean(trip.maxLeanRight))
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func figure(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
