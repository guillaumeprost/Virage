import MapKit
import SwiftUI

struct DashboardView: View {
    @Environment(RideEngine.self) private var engine
    @Environment(PhoneConnectivity.self) private var connectivity
    @Environment(NavigationController.self) private var navigation
    @Environment(NowPlaying.self) private var music
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    /// Shared between the four layouts, so each block slides to its new place when the phone rotates or
    /// navigation starts, instead of popping in.
    @Namespace private var layout
    /// Ties the map's controls, placed by the layouts, to the map.
    @Namespace private var mapScope

    private enum Block: Hashable {
        case status, banner, speed, gauge, metrics, map, button
    }

    @State private var isConfirmingEnd = false
    @State private var isShowingFuel = false
    @State private var isShowingScenic = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dashboardStyle) private var style

    var body: some View {
        let snapshot = engine.snapshot
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            Group {
                if let route = navigation.guidance?.route {
                    if isLandscape {
                        navigationLandscape(snapshot, route: route)
                    } else {
                        navigationPortrait(snapshot, route: route)
                    }
                } else if isLandscape {
                    rideLandscape(snapshot, height: geometry.size.height)
                        .padding(.vertical, 8)
                } else {
                    ridePortrait(snapshot)
                        .padding()
                }
            }
            .animation(.smooth(duration: 0.4), value: isLandscape)
            .animation(.smooth(duration: 0.4), value: navigation.guidance?.route.destination)
            .animation(.smooth(duration: 0.3), value: music.isVisible)
        }
        // In landscape at rest, every pixel of height counts. During a ride the dashboard covers the tabs anyway.
        .toolbarVisibility(verticalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .persistentSystemOverlays(snapshot.isRiding ? .hidden : .automatic)
        .background(style.background.ignoresSafeArea())
        .sheet(isPresented: $isShowingFuel) {
            FuelSheet()
        }
        .sheet(isPresented: $isShowingScenic) {
            ScenicSheet()
        }
        // Reaching the reserve: felt in the hand, since the badge turning red is easy to miss on the road.
        .sensoryFeedback(.warning, trigger: engine.fuelWarnings)
        .confirmationDialog("Terminer le trajet ?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("Terminer le trajet", role: .destructive) {
                engine.stopRide()
            }
        } message: {
            Text("Il sera enregistré dans Trajets.")
        }
        .overlay {
            if engine.isLocationDenied {
                ContentUnavailableView {
                    Label("GPS désactivé", systemImage: "location.slash")
                } description: {
                    Text("Autorise la localisation pour Virage dans Réglages pour afficher ta vitesse.")
                } actions: {
                    Button("Ouvrir Réglages") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .background(Color(.systemBackground))
            }
        }
    }

    // MARK: Layouts

    /// The speed takes whatever height the rest leaves: more once the tab bar hides for the ride.
    private func ridePortrait(_ snapshot: RideSnapshot) -> some View {
        VStack(spacing: 20) {
            place(statusBar, .status)
            place(FittedSpeedDisplay(snapshot: snapshot, unit: unit, sizes: 140...300), .speed)
            place(LeanGaugeView(snapshot: snapshot), .gauge)
            place(metrics(snapshot), .metrics)
            musicBar()
            place(rideControls(), .button)
        }
    }

    /// The speed takes the left half, as tall as the screen allows.
    private func rideLandscape(_ snapshot: RideSnapshot, height: CGFloat) -> some View {
        HStack(spacing: 20) {
            if snapshot.isRiding {
                // The round controls along the edge, by the Dynamic Island: the speed gets the full height.
                place(rideControls(vertical: true), .button)
                place(speed(snapshot, size: height * 0.7), .speed)
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    place(speed(snapshot, size: height * 0.55), .speed)
                        .frame(maxHeight: .infinity)
                    place(rideControls(), .button)
                }
            }
            VStack(spacing: 10) {
                place(statusBar, .status)
                place(LeanGaugeView(snapshot: snapshot, dialHeight: 80), .gauge)
                place(metrics(snapshot), .metrics)
                musicBar()
            }
            .frame(maxWidth: 400)
        }
    }

    /// As in Maps: the map fills the screen, the next turn floats on top and the ride sits in a panel below.
    private func navigationPortrait(_ snapshot: RideSnapshot, route: NavigationRoute) -> some View {
        ZStack {
            map(route, snapshot, clearance: navigation.nextStop == nil ? 110 : 160, bottom: 170)
            VStack(spacing: 0) {
                place(banner, .banner)
                mapControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 10)
                Spacer(minLength: 0)
                // The music on the left, the badges on the right: beside them, only the cover and the two
                // buttons that matter on the road fit.
                HStack(spacing: 10) {
                    musicBar(isCompact: true)
                    Spacer(minLength: 0)
                    badges
                }
                .padding(.bottom, 8)
                HStack(spacing: 16) {
                    place(speed(snapshot, size: 88), .speed)
                    place(compactMetrics(snapshot), .metrics)
                        .frame(maxWidth: 130)
                    place(rideControls(vertical: true), .button)
                }
                .padding(14)
                .background(.regularMaterial, in: .rect(cornerRadius: 28))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .mapScope(mapScope)
    }

    /// The speed first: it fills the panel, the rest stays small beneath it. The fuel badge floats over the map,
    /// out of the panel.
    private func navigationLandscape(_ snapshot: RideSnapshot, route: NavigationRoute) -> some View {
        ZStack(alignment: .topLeading) {
            // The rider just above the badges, bottom left.
            map(route, snapshot, clearance: 20, bottom: 65, trailing: 330, lift: 45)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    place(banner, .banner)
                        .frame(maxWidth: 420)
                    Spacer(minLength: 0)
                    badges
                }
                Spacer(minLength: 0)
                mapControls
                // The music joins the panel, off the map; the speed gives up the height it needs.
                VStack(spacing: 12) {
                    place(FittedSpeedDisplay(snapshot: snapshot, unit: unit, sizes: 80...160), .speed)
                    place(compactMetrics(snapshot, horizontal: true), .metrics)
                    musicBar(showsPrevious: false)
                    place(rideControls(), .button)
                }
                .padding(14)
                .frame(width: 270)
                .frame(maxHeight: .infinity)
                .background(.regularMaterial, in: .rect(cornerRadius: 28))
            }
            .padding()
        }
        .mapScope(mapScope)
    }

    private func place(_ content: some View, _ block: Block) -> some View {
        content.matchedGeometryEffect(id: block, in: layout)
    }

    // MARK: Blocks

    /// How far above the bottom panel the rider sits: clear of the row of badges and music above it.
    private static let riderLift: CGFloat = 130

    /// The rider low on the map, just above `bottom`, as in a car's navigation: the road ahead and the
    /// coming bends fill the screen. MapKit centers the position, and the recentre button, in the safe
    /// area: a tall inset on top brings that center down. `clearance` is the least the banner needs.
    private func map(
        _ route: NavigationRoute,
        _ snapshot: RideSnapshot,
        clearance: CGFloat,
        bottom: CGFloat,
        trailing: CGFloat = 0,
        lift: CGFloat = riderLift
    ) -> some View {
        GeometryReader { proxy in
            RideMapView(route: route, position: snapshot.position, controlsScope: mapScope)
                .equatable()
                .safeAreaPadding(.top, max(clearance, proxy.size.height - bottom - 2 * lift))
                .safeAreaPadding(.bottom, bottom)
                .safeAreaPadding(.trailing, trailing)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private func compactMetrics(_ snapshot: RideSnapshot, horizontal: Bool = false) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
        return layout {
            MetricTile(title: "Inclinaison", value: Format.lean(snapshot.leanAngle))
            MetricTile(title: "Distance", value: Format.distance(snapshot.distance, unit))
        }
    }

    private var statusBar: some View {
        HStack {
            if engine.snapshot.isRiding {
                Label("Trajet en cours", systemImage: "record.circle")
                    .foregroundStyle(.red)
            }
            Spacer()
            badges
            if connectivity.isWatchAppInstalled {
                Image(systemName: connectivity.isWatchReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .foregroundStyle(connectivity.isWatchReachable ? .green : .secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    /// Recentre and compass, stacked: placed by each layout clear of the banner and the panel.
    private var mapControls: some View {
        VStack(spacing: 10) {
            MapUserLocationButton(scope: mapScope)
            MapCompass(scope: mapScope)
        }
        .buttonBorderShape(.circle)
    }

    /// Apple Music, only while it plays.
    @ViewBuilder
    private func musicBar(isCompact: Bool = false, showsPrevious: Bool = true) -> some View {
        if music.isVisible {
            MusicCapsule(music: music, isCompact: isCompact, showsPrevious: showsPrevious)
        }
    }

    /// The small badges, side by side: passes and viewpoints, then the tank.
    private var badges: some View {
        HStack(spacing: 10) {
            ScenicBadge { isShowingScenic = true }
            FuelBadge(sinceRefuel: engine.sinceRefuel, fuel: engine.fuel) { isShowingFuel = true }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let state = navigation.state {
            NavigationBanner(
                state: state,
                course: engine.snapshot.course,
                isRerouting: navigation.isRerouting,
                nextStop: navigation.nextStop,
                onSkipStop: navigation.skipNextStop,
                onStop: navigation.stop
            )
        }
    }

    private func speed(_ snapshot: RideSnapshot, size: CGFloat) -> some View {
        SpeedDisplay(snapshot: snapshot, unit: unit, size: size)
    }

    private func metrics(_ snapshot: RideSnapshot) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricTile(title: "Distance", value: Format.distance(snapshot.distance, unit))
                MetricTile(title: "Temps", value: Format.duration(snapshot.movingTime))
                MetricTile(title: "Max", value: "\(Format.speed(snapshot.maxSpeed, unit)) \(unit.speedLabel)")
            }
            GridRow {
                MetricTile(title: "Moyenne", value: "\(Format.speed(snapshot.averageSpeed, unit)) \(unit.speedLabel)")
                MetricTile(title: "Altitude", value: Format.altitude(snapshot.altitude, unit))
                MetricTile(title: "Cap", value: Format.course(snapshot.course))
            }
        }
    }

    /// At rest, one wide button to ride. Riding, two round ones, apart: pause, and ending under a checkered flag.
    @ViewBuilder
    private func rideControls(vertical: Bool = false) -> some View {
        if engine.snapshot.isRiding {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 48))
            layout {
                RoundButton(
                    systemImage: engine.snapshot.isPaused ? "play.fill" : "pause.fill",
                    label: engine.snapshot.isPaused ? "Reprendre" : "Pause",
                    foreground: .primary,
                    background: style == .classic ? Color(.tertiarySystemFill) : Color.primary.opacity(0.1)
                ) {
                    engine.setPaused(!engine.snapshot.isPaused)
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: engine.snapshot.isPaused)

                RoundButton(systemImage: "flag.checkered", label: "Terminer le trajet", foreground: .white, background: .red) {
                    isConfirmingEnd = true
                }
            }
            .frame(maxWidth: vertical ? nil : .infinity)
        } else {
            Button {
                engine.startRide()
            } label: {
                Label("Démarrer un trajet", systemImage: "play.fill")
                    .font(style.figureFont(.title3.weight(.bold), size: 20, relativeTo: .title3))
                    .styledDigits(style)
                    .foregroundStyle(style.onTint)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(style == .sport ? .roundedRectangle(radius: 12) : .capsule)
            .sensoryFeedback(.impact(weight: .heavy), trigger: engine.snapshot.isRiding)
        }
    }
}

/// A round control sized for gloves.
private struct RoundButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let foreground: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(foreground)
                .frame(width: 64, height: 64)
                .background(background, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    @Environment(\.dashboardStyle) private var style

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(style.labelFont(.caption.weight(.semibold), size: 13, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(style == .retro ? 1 : 0)
            Text(value)
                .font(style.figureFont(.headline, size: 18, relativeTo: .headline))
                .styledDigits(style)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            let shape = RoundedRectangle(cornerRadius: style == .sport ? 8 : 12)
            if style == .classic {
                shape.fill(Color(.secondarySystemBackground))
            } else {
                shape.strokeBorder(style.outline, lineWidth: 1)
            }
        }
    }
}
