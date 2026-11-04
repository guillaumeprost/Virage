import SwiftUI

struct DashboardView: View {
    @Environment(RideEngine.self) private var engine
    @Environment(PhoneConnectivity.self) private var connectivity
    @Environment(NavigationController.self) private var navigation
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    /// Shared between the four layouts, so each block slides to its new place when the phone rotates or
    /// navigation starts, instead of popping in.
    @Namespace private var layout

    private enum Block: Hashable {
        case status, banner, speed, gauge, metrics, map, button
    }

    @State private var isConfirmingEnd = false
    @State private var isShowingFuel = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
        }
        // In landscape at rest, every pixel of height counts. During a ride the dashboard covers the tabs anyway.
        .toolbarVisibility(verticalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .persistentSystemOverlays(snapshot.isRiding ? .hidden : .automatic)
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $isShowingFuel) {
            FuelSheet()
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

    private func ridePortrait(_ snapshot: RideSnapshot) -> some View {
        VStack(spacing: 20) {
            place(statusBar, .status)
            place(speed(snapshot, size: 200), .speed)
            place(LeanGaugeView(snapshot: snapshot), .gauge)
            place(metrics(snapshot), .metrics)
            Spacer(minLength: 0)
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
            }
            .frame(maxWidth: 400)
        }
    }

    /// As in Maps: the map fills the screen, the next turn floats on top and the ride sits in a panel below.
    private func navigationPortrait(_ snapshot: RideSnapshot, route: NavigationRoute) -> some View {
        ZStack {
            map(route, snapshot)
                // Keeps the rider's position and the map controls clear of the banner and the panel.
                .safeAreaPadding(.top, navigation.nextStop == nil ? 110 : 160)
                .safeAreaPadding(.bottom, 170)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                place(banner, .banner)
                Spacer(minLength: 0)
                fuelBadge
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
    }

    private func navigationLandscape(_ snapshot: RideSnapshot, route: NavigationRoute) -> some View {
        ZStack(alignment: .topLeading) {
            map(route, snapshot)
                .safeAreaPadding(.trailing, 330)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 16) {
                place(banner, .banner)
                    .frame(maxWidth: 420)
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    place(speed(snapshot, size: 110), .speed)
                    place(compactMetrics(snapshot), .metrics)
                    fuelBadge
                    Spacer(minLength: 0)
                    place(rideControls(), .button)
                }
                .padding(14)
                .frame(width: 250)
                .frame(maxHeight: .infinity)
                .background(.regularMaterial, in: .rect(cornerRadius: 28))
            }
            .padding()
        }
    }

    private func place(_ content: some View, _ block: Block) -> some View {
        content.matchedGeometryEffect(id: block, in: layout)
    }

    // MARK: Blocks

    private func map(_ route: NavigationRoute, _ snapshot: RideSnapshot) -> some View {
        RideMapView(route: route, position: snapshot.position)
            .equatable()
    }

    private func compactMetrics(_ snapshot: RideSnapshot) -> some View {
        VStack(spacing: 8) {
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
            fuelBadge
            if connectivity.isWatchAppInstalled {
                Image(systemName: connectivity.isWatchReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .foregroundStyle(connectivity.isWatchReachable ? .green : .secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder
    private var fuelBadge: some View {
        if let fuel = engine.fuel {
            FuelBadge(fuel: fuel) { isShowingFuel = true }
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
        VStack(spacing: 0) {
            Text(Format.speed(snapshot.speed, unit))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .contentTransition(.numericText(value: snapshot.speed))
                .animation(.snappy, value: Int(unit.speed(snapshot.speed)))
                .foregroundStyle(snapshot.isPaused ? .secondary : .primary)
            if snapshot.isPaused {
                Label("En pause", systemImage: "pause.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(unit.speedLabel)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
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
                    background: Color(.tertiarySystemFill)
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
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
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

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}
