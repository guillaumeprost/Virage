import MapKit
import SwiftData
import SwiftUI

struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @State private var renaming: Trip?

    var body: some View {
        let figures = trips.map(\.figures)
        // Grouped once, for the rows and for deleting.
        let tripsByMonth = Dictionary(grouping: trips) { TripInsights.monthStart(of: $0.startDate) }
        NavigationStack {
            List {
                if !trips.isEmpty {
                    records(figures)
                }
                ForEach(TripInsights.months(figures)) { month in
                    Section {
                        let monthTrips = tripsByMonth[month.month] ?? []
                        ForEach(monthTrips) { trip in
                            NavigationLink(value: trip) {
                                row(trip)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Renommer", systemImage: "pencil") { renaming = trip }
                                    .tint(.blue)
                            }
                            .contextMenu {
                                Button("Renommer", systemImage: "pencil") { renaming = trip }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { monthTrips[$0] }.forEach(modelContext.delete)
                        }
                    } header: {
                        monthHeader(month)
                    }
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
            .renameTrip($renaming)
            .task { measureOlderTrips() }
        }
    }

    /// Trips recorded before elevation was kept: measured once from their track.
    private func measureOlderTrips() {
        for trip in trips where trip.maxAltitude == 0 {
            trip.measureElevation(trip.track)
        }
    }

    private func row(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.title)
                .font(.headline)
            if trip.name != nil {
                Text(trip.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(Format.distance(trip.distance, unit)) · \(Format.duration(trip.movingTime)) · max \(Format.speed(trip.maxSpeed, unit)) \(unit.speedLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// The month and its totals: the monthly summary, read as the list scrolls.
    private func monthHeader(_ month: MonthSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.month.formatted(.dateTime.month(.wide).year()).capitalized)
            Spacer()
            Text("\(month.count) \(month.count == 1 ? "trajet" : "trajets") · \(Format.range(month.distance, unit)) · \(Format.shortDuration(month.movingTime))")
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func records(_ figures: [TripFigures]) -> some View {
        Section("Records") {
            if let index = TripInsights.record(figures, by: \.distance) {
                record("Plus longue sortie", Format.distance(figures[index].distance, unit), systemImage: "road.lanes", trip: trips[index])
            }
            if let index = TripInsights.record(figures, by: \.maxSpeed) {
                record("Vitesse max", "\(Format.speed(figures[index].maxSpeed, unit)) \(unit.speedLabel)", systemImage: "gauge.with.needle", trip: trips[index])
            }
            if let index = TripInsights.record(figures, by: \.maxLean) {
                record("Inclinaison max", Format.lean(figures[index].maxLean), systemImage: "angle", trip: trips[index])
            }
            if let index = TripInsights.record(figures, by: \.elevationGain) {
                record("Plus de dénivelé", "+ " + Format.altitude(figures[index].elevationGain, unit), systemImage: "arrow.up.right", trip: trips[index])
            }
            if let index = TripInsights.record(figures, by: \.maxAltitude) {
                record("Plus haut", Format.altitude(figures[index].maxAltitude, unit), systemImage: "mountain.2", trip: trips[index])
            }
            if let index = TripInsights.record(figures, by: \.movingTime) {
                record("Plus longue en temps", Format.shortDuration(figures[index].movingTime), systemImage: "clock", trip: trips[index])
            }
        }
    }

    private func record(_ title: String, _ value: String, systemImage: String, trip: Trip) -> some View {
        NavigationLink(value: trip) {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(trip.name ?? trip.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .lineLimit(1)
                }
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

extension Trip {
    var figures: TripFigures {
        TripFigures(
            start: startDate,
            distance: distance,
            movingTime: movingTime,
            maxSpeed: maxSpeed,
            maxLean: max(maxLeanLeft, maxLeanRight),
            elevationGain: elevationGain,
            maxAltitude: maxAltitude
        )
    }
}

/// Same layout as the route preview: the map fills the screen, the figures sit in a panel at the bottom. The
/// track is colored by speed or lean, and the most leaned bends are pinned.
struct TripDetailView: View {
    let trip: Trip
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @AppStorage("tripColoring") private var coloring = TrackColoring.speed
    @State private var track: [TrackPoint] = []
    @State private var segments: [TrackSegment] = []
    @State private var peaks: [LeanPeak] = []
    @State private var photos: [TripPhoto] = []
    @State private var photoAccess = TripPhotos.status
    @State private var shownPhoto: TripPhoto?
    @State private var isSharing = false
    @State private var renaming: Trip?

    /// Trips recorded before lean was kept along the track, or on the Watch alone, can only show speed.
    @State private var hasLean = false

    private var shownColoring: TrackColoring {
        hasLean ? coloring : .speed
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(TrackColoring.color(for: segment.band), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let first = track.first {
                Marker("Départ", systemImage: "flag", coordinate: first.coordinate).tint(.green)
            }
            if let last = track.last {
                Marker("Arrivée", systemImage: "flag.checkered", coordinate: last.coordinate).tint(.red)
            }
            ForEach(trip.passes) { pass in
                Marker(pass.name, systemImage: "mountain.2.fill", coordinate: pass.coordinate)
                    .tint(.brown)
            }
            ForEach(photos) { photo in
                Annotation("", coordinate: photo.coordinate) {
                    Button {
                        shownPhoto = photo
                    } label: {
                        Image(uiImage: photo.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 2))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo de \(photo.date.formatted(date: .omitted, time: .shortened))")
                }
            }
            ForEach(peaks) { peak in
                Annotation("", coordinate: peak.coordinate) {
                    Text("\(Format.lean(peak.lean)) \(peak.lean < 0 ? "G" : "D")")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red, in: .capsule)
                        .accessibilityLabel("Virage penché à \(Format.lean(peak.lean)) \(peak.lean < 0 ? "à gauche" : "à droite")")
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            summary
        }
        .navigationTitle(trip.name ?? trip.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .renameTrip($renaming)
        .toolbar {
            Button("Renommer", systemImage: "pencil") { renaming = trip }
            Menu {
                Button("Partager une image", systemImage: "photo") {
                    isSharing = true
                }
                ShareLink(item: GPXFile(trip: trip), preview: SharePreview("Trajet GPX")) {
                    Label("Exporter en GPX", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            } label: {
                Label("Partager", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $isSharing) {
            TripShareSheet(trip: trip, track: track)
        }
        .sheet(item: $shownPhoto) { photo in
            TripPhotoViewer(photo: photo)
        }
        .task {
            // Decoded once: a long ride holds thousands of points.
            track = trip.track
            hasLean = track.contains { $0.lean != nil }
            peaks = TripInsights.leanPeaks(track)
            segments = TripInsights.segments(track, by: shownColoring)
            // The photos and the passes are looked up side by side.
            let route = trip.passesChecked ? nil : track.map(\.position)
            async let passes = Self.passes(along: route)
            photos = await TripPhotos.load(from: trip.startDate, to: trip.endDate, track: track)
            if let passes = await passes {
                trip.passes = passes
                trip.passesChecked = true
            }
        }
        .onChange(of: coloring) {
            segments = TripInsights.segments(track, by: shownColoring)
        }
    }

    /// Nil when the trip's passes were already looked up.
    private static func passes(along route: [Coordinate]?) async -> [TripPass]? {
        guard let route else { return nil }
        return await ScenicSearch.passes(along: route)
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

            if trip.maxAltitude != 0 {
                HStack(alignment: .top) {
                    figure("Dénivelé +", Format.altitude(trip.elevationGain, unit))
                    figure("Alt. max", Format.altitude(trip.maxAltitude, unit))
                    figure("Cols", trip.passesChecked ? "\(trip.passes.count)" : "…")
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }

            if !trip.passes.isEmpty {
                Label(trip.passes.map(\.name).formatted(.list(type: .and)), systemImage: "mountain.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if photoAccess == .notDetermined {
                Button("Afficher mes photos de la sortie", systemImage: "photo.on.rectangle") {
                    Task {
                        await TripPhotos.requestAccess()
                        photoAccess = TripPhotos.status
                        photos = await TripPhotos.load(from: trip.startDate, to: trip.endDate, track: track)
                    }
                }
                .frame(minHeight: 44)
            } else if !photos.isEmpty {
                Label(photos.count == 1 ? "1 photo de la sortie" : "\(photos.count) photos de la sortie", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if hasLean {
                Picker("Couleur de la trace", selection: $coloring) {
                    ForEach(TrackColoring.allCases) { coloring in
                        Text(coloring.label).tag(coloring)
                    }
                }
                .pickerStyle(.segmented)
            }
            legend
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// The color bands, with the value each one starts at.
    private var legend: some View {
        let labels = shownColoring.legend(unit)
        return HStack(spacing: 6) {
            ForEach(labels.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(TrackColoring.colors[index])
                        .frame(height: 6)
                    Text(labels[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trace colorée selon \(shownColoring.label.lowercased()), du bleu au rouge")
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

/// Naming a trip, from the list or from its page.
private struct RenameTrip: ViewModifier {
    @Binding var trip: Trip?
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert("Renommer le trajet", isPresented: Binding(get: { trip != nil }, set: { if !$0 { trip = nil } })) {
                TextField("Tour du lac, Les Aravis…", text: $text)
                    .textInputAutocapitalization(.sentences)
                Button("Annuler", role: .cancel) {}
                Button("Renommer") { trip?.rename(text) }
            } message: {
                Text("Laisse vide pour revenir à la date.")
            }
            .onChange(of: trip) {
                text = trip?.name ?? ""
            }
    }
}

extension View {
    func renameTrip(_ trip: Binding<Trip?>) -> some View {
        modifier(RenameTrip(trip: trip))
    }
}

