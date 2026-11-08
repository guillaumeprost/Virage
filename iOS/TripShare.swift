import CoreTransferable
import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// A rendered image of a trip, shared as a PNG file: transparency survives, for stickers.
struct SharedImage: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { $0.name }
    }
}

/// The trip's line, fitted to a frame and kept in proportion: the shape of the ride, without the map.
struct TraceGeometry {
    /// Each stretch of track in the frame's unit square, with its color band.
    let stretches: [(band: Int?, points: [CGPoint])]
    /// Width over height of the ride's outline.
    let aspectRatio: CGFloat

    init(track: [TrackPoint], coloring: TrackColoring) {
        let segments = TripInsights.segments(track, by: coloring)
        let latitudes = track.map(\.latitude)
        let longitudes = track.map(\.longitude)
        let meanLatitude = ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2
        // Degrees of longitude shrink away from the equator: scaled so the outline is not stretched sideways.
        let xScale = cos(meanLatitude * .pi / 180)
        let minX = (longitudes.min() ?? 0) * xScale
        let maxX = (longitudes.max() ?? 0) * xScale
        let minY = latitudes.min() ?? 0
        let maxY = latitudes.max() ?? 0
        let width = max(maxX - minX, 1e-9)
        let height = max(maxY - minY, 1e-9)
        aspectRatio = CGFloat(width / height)
        stretches = segments.map { segment in
            (segment.band, segment.coordinates.map { coordinate in
                CGPoint(x: (coordinate.longitude * xScale - minX) / width, y: (maxY - coordinate.latitude) / height)
            })
        }
    }
}

/// The line alone, drawn to fill its frame: white, or in the colors of the bands.
struct TraceDrawing: View {
    let geometry: TraceGeometry
    let colored: Bool
    var lineWidth: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let inset = lineWidth
            let drawable = CGSize(width: size.width - inset * 2, height: size.height - inset * 2)
            for stretch in geometry.stretches {
                var path = Path()
                path.addLines(stretch.points.map { CGPoint(x: inset + $0.x * drawable.width, y: inset + $0.y * drawable.height) })
                let color = colored ? TrackColoring.color(for: stretch.band) : .white
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(geometry.aspectRatio, contentMode: .fit)
    }
}

/// The figures every image shows.
private struct ShareFigures {
    let items: [(label: String, value: String)]

    init(trip: Trip, unit: SpeedUnit) {
        var items: [(String, String)] = [
            ("Distance", Format.distance(trip.distance, unit)),
            ("Temps", Format.shortDuration(trip.movingTime)),
        ]
        if trip.maxAltitude != 0 {
            items.append(("D+", Format.altitude(trip.elevationGain, unit)))
        }
        items.append(("Inclinaison", Format.lean(max(trip.maxLeanLeft, trip.maxLeanRight))))
        self.items = items
    }
}

/// The Strava-like sticker: the line and the figures in white, on nothing, to lay over a photo.
struct TraceSticker: View {
    let trip: Trip
    let geometry: TraceGeometry
    let colored: Bool
    let unit: SpeedUnit
    let style: DashboardStyle

    var body: some View {
        VStack(spacing: 22) {
            if let name = trip.name {
                Text(name)
                    .font(style.figureFont(.title2.weight(.bold), size: 24, relativeTo: .title2))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            TraceDrawing(geometry: geometry, colored: colored, lineWidth: 6)
                .frame(maxWidth: 300, maxHeight: 300)
            HStack(alignment: .top, spacing: 16) {
                ForEach(ShareFigures(trip: trip, unit: unit).items, id: \.label) { item in
                    VStack(spacing: 3) {
                        Text(item.label.uppercased())
                            .font(style.labelFont(.caption2.weight(.semibold), size: 10, relativeTo: .caption2))
                            .tracking(1)
                            .opacity(0.85)
                        Text(item.value)
                            .font(style.figureFont(.title3.weight(.bold), size: 20, relativeTo: .title3))
                            .styledDigits(style)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            if !trip.passes.isEmpty {
                Label(trip.passes.map(\.name).formatted(.list(type: .and)), systemImage: "mountain.2.fill")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            Text("VIRAGE")
                .font(.caption.weight(.heavy))
                .tracking(4)
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 380)
    }
}

/// The card: the map with the line on it, the figures below, in the look of the dashboard.
struct TripCard: View {
    let trip: Trip
    let map: UIImage?
    let stretches: [(band: Int?, points: [CGPoint])]
    let unit: SpeedUnit
    let style: DashboardStyle

    static let mapSize = CGSize(width: 360, height: 300)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let map {
                    Image(uiImage: map)
                        .resizable()
                } else {
                    Rectangle().fill(.quaternary)
                }
                Canvas { context, _ in
                    for stretch in stretches {
                        var path = Path()
                        path.addLines(stretch.points)
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        let color = TrackColoring.color(for: stretch.band)
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(width: Self.mapSize.width, height: Self.mapSize.height)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let name = trip.name {
                        Text(name)
                            .font(style.figureFont(.title3.weight(.bold), size: 20, relativeTo: .title3))
                            .lineLimit(2)
                    }
                    Text(trip.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                        .font(style.labelFont(.subheadline.weight(.semibold), size: 13, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    let items = ShareFigures(trip: trip, unit: unit).items
                    GridRow {
                        ForEach(items.prefix(2), id: \.label) { figure($0) }
                    }
                    GridRow {
                        ForEach(items.dropFirst(2), id: \.label) { figure($0) }
                    }
                }
                if !trip.passes.isEmpty {
                    Label(trip.passes.map(\.name).formatted(.list(type: .and)), systemImage: "mountain.2.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack {
                    Spacer()
                    Text("VIRAGE")
                        .font(.caption2.weight(.heavy))
                        .tracking(3)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(18)
            .frame(width: Self.mapSize.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(style.background)
    }

    private func figure(_ item: (label: String, value: String)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.value)
                .font(style.figureFont(.title2.weight(.bold), size: 22, relativeTo: .title2))
                .styledDigits(style)
                .monospacedDigit()
            Text(item.label.uppercased())
                .font(style.labelFont(.caption2.weight(.semibold), size: 10, relativeTo: .caption2))
                .foregroundStyle(.secondary)
        }
    }
}

/// Choosing and sharing an image of the trip.
struct TripShareSheet: View {
    let trip: Trip
    let track: [TrackPoint]

    enum Kind: String, CaseIterable, Identifiable {
        case card, sticker
        var id: Self { self }
        var label: String { self == .card ? "Carte" : "Tracé transparent" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dashboardStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @AppStorage("shareKind") private var kind = Kind.card
    @AppStorage("shareColoredTrace") private var coloredTrace = false
    @State private var map: UIImage?
    @State private var mapStretches: [(band: Int?, points: [CGPoint])] = []
    @State private var image: SharedImage?
    /// Built once: it smooths and scales the whole track.
    @State private var geometry: TraceGeometry?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Image", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if kind == .sticker {
                    Toggle("Tracé en couleurs (vitesse)", isOn: $coloredTrace)
                }

                if let image {
                    ShareLink(item: image, preview: SharePreview(kind.label, image: Image(systemName: "photo"))) {
                        Label("Partager l'image", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ProgressView()
                        .frame(minHeight: 50)
                }
            }
            .padding()
            .navigationTitle("Partager le trajet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task {
                geometry = TraceGeometry(track: track, coloring: .speed)
                await loadMap()
            }
            .onChange(of: kind) { render() }
            .onChange(of: coloredTrace) { render() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch kind {
        case .card:
            card
                .clipShape(.rect(cornerRadius: 16))
                .shadow(radius: 6)
                .scaleEffect(0.85)
        case .sticker:
            // A dark, photo-like backdrop shows the white line; it is not part of the image.
            sticker
                .background(
                    LinearGradient(colors: [Color(white: 0.35), Color(white: 0.15)], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 16)
                )
                .scaleEffect(0.85)
        }
    }

    private var card: some View {
        TripCard(trip: trip, map: map, stretches: mapStretches, unit: unit, style: style)
            .environment(\.colorScheme, colorScheme)
    }

    @ViewBuilder
    private var sticker: some View {
        if let geometry {
            TraceSticker(trip: trip, geometry: geometry, colored: coloredTrace, unit: unit, style: style)
        }
    }

    /// 1080 px wide: what Instagram and WhatsApp show without scaling.
    private func render() {
        let content: AnyView = kind == .card ? AnyView(card) : AnyView(sticker)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = kind == .card
        image = renderer.uiImage?.pngData().map { SharedImage(data: $0, name: "\(trip.fileTitle).png") }
    }

    /// A map of the ride's area, in the dashboard's light or dark look, with the line placed on it.
    private func loadMap() async {
        defer { render() }
        let coordinates = track.map(\.coordinate)
        guard coordinates.count >= 2 else { return }
        var polyline = coordinates
        let rect = MKPolyline(coordinates: &polyline, count: polyline.count).boundingMapRect
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
        options.size = TripCard.mapSize
        options.scale = 3
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }
        map = snapshot.image
        mapStretches = TripInsights.segments(track, by: .speed).map { segment in
            (segment.band, segment.coordinates.map { snapshot.point(for: $0) })
        }
    }
}
