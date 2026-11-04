import SwiftUI

struct WatchRideView: View {
    @Environment(WatchRideModel.self) private var model

    var body: some View {
        if model.isRiding {
            RideSessionView()
        } else {
            StartView()
        }
    }
}

/// Before a ride: one big button to ride, then a destination and the settings below.
private struct StartView: View {
    @Environment(WatchRideModel.self) private var model
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Button {
                    model.startRide()
                } label: {
                    Label("Démarrer", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .handGestureShortcut(.primaryAction)
                .listRowBackground(Color.clear)

                NavigationLink {
                    WatchDestinationView {
                        path = NavigationPath()
                    }
                } label: {
                    Label("Destination", systemImage: "location.magnifyingglass")
                }
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Réglages", systemImage: "gearshape")
                }
            }
            .navigationTitle("Virage")
        }
    }
}

/// Laid out like the Workout app: controls on the left page, metrics on the right one, scrolled vertically
/// with the Digital Crown.
private struct RideSessionView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var page = Page.metrics

    private enum Page {
        case controls, metrics
    }

    var body: some View {
        // Hidden rather than replaced while the wrist is down, so the rider finds the same page on raising it.
        TabView(selection: $page) {
            ControlsPage {
                // The guidance page comes to the front on its own; this brings its column into view.
                withAnimation { page = .metrics }
            }
            .tag(Page.controls)
            MetricsPages()
                .tag(Page.metrics)
        }
        .tabViewStyle(.page)
        .opacity(isLuminanceReduced ? 0 : 1)
        // Hidden is not enough: a tap would still reach the buttons underneath.
        .allowsHitTesting(!isLuminanceReduced)
        .overlay {
            if isLuminanceReduced {
                AlwaysOnView()
            }
        }
    }
}

private struct ControlsPage: View {
    @Environment(WatchRideModel.self) private var model
    @State private var isChoosingDestination = false
    let onNavigate: () -> Void

    var body: some View {
        // Two rows, always on one screen. With a stop ahead, skipping it takes the first place, by the end button;
        // otherwise pause does.
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                if model.nextStop != nil {
                    ControlButton(title: "Passer l'étape", systemImage: "forward.end.fill", color: .cyan) {
                        model.skipNextStop()
                    }
                } else {
                    pauseButton
                }
                ControlButton(title: "Terminer", systemImage: "xmark", color: .red) {
                    model.stopRide()
                }
            }
            GridRow {
                if model.nextStop != nil {
                    pauseButton
                    routeButton
                } else {
                    routeButton
                        .gridCellColumns(2)
                }
            }
        }
        .sheet(isPresented: $isChoosingDestination) {
            NavigationStack {
                WatchDestinationView {
                    isChoosingDestination = false
                    onNavigate()
                }
            }
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        if model.snapshot.isPaused {
            ControlButton(title: "Reprendre", systemImage: "play.fill", color: .green) {
                model.setPaused(false)
            }
        } else {
            ControlButton(title: "Pause", systemImage: "pause.fill", color: .yellow) {
                model.setPaused(true)
            }
        }
    }

    @ViewBuilder
    private var routeButton: some View {
        if model.guidance != nil {
            ControlButton(title: "Fin guidage", systemImage: "location.slash.fill", color: .blue) {
                model.stopNavigation()
            }
        } else {
            ControlButton(title: "Destination", systemImage: "location.magnifyingglass", color: .blue) {
                isChoosingDestination = true
            }
        }
    }
}

private struct ControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 64, height: 48)
            }
            .buttonStyle(.bordered)
            .tint(color)
            Text(title)
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// One view per screen, as in the Workout app; the Digital Crown scrolls through them.
///
/// A paging scroll view rather than a vertical `TabView`: nested in the horizontal pages, a vertical
/// `TabView` loses the swipe to its parent and never moves.
private struct MetricsPages: View {
    @Environment(WatchRideModel.self) private var model
    @State private var page: Page? = .speed

    private enum Page {
        case navigation, map, speed, lean, totals, terrain
    }

    private var pages: [Page] {
        var pages: [Page] = model.guidance == nil ? [] : [.navigation, .map]
        pages.append(.speed)
        // The lean angle is measured by the iPhone's gyroscope: on its own, the Watch has none to show.
        if model.source == .phone {
            pages.append(.lean)
        }
        return pages + [.totals, .terrain]
    }

    var body: some View {
        // Pages exactly one screen tall, scrolled one screen at a time: the scroll view covers the whole
        // screen, and only each page's content keeps clear of the clock. Scrolling within the safe area
        // instead leaves pages misaligned, half of one and half of the next.
        GeometryReader { safeArea in
            let insets = safeArea.safeAreaInsets
            GeometryReader { screen in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(pages, id: \.self) { page in
                            content(page)
                                .padding(.top, insets.top)
                                .padding(.bottom, insets.bottom)
                                .padding(.horizontal, 4)
                                .frame(width: screen.size.width, height: screen.size.height)
                        }
                    }
                    .scrollTargetLayout()
                }
                // watchOS adds its own margins to scroll content, which would shift every page off the grid.
                .contentMargins(0, for: .scrollContent)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if model.guidance != nil {
                page = .navigation
            }
        }
        .onChange(of: model.guidance?.route.id) { _, routeID in
            // A new route brings the arrow to the front; navigation ending falls back to the speed.
            withAnimation {
                page = routeID == nil ? .speed : .navigation
            }
        }
    }

    @ViewBuilder
    private func content(_ page: Page) -> some View {
        let snapshot = model.snapshot
        let unit = model.unit
        switch page {
        case .navigation:
            if let guidance = model.guidance {
                WatchNavigationView(state: guidance.state, snapshot: snapshot, unit: unit, isRerouting: model.isRerouting)
            }
        case .map:
            if let guidance = model.guidance {
                RideMapView(route: guidance.route, position: snapshot.position, isInteractive: false)
                    .equatable()
                    .clipShape(.rect(cornerRadius: 20))
            }
        case .speed:
            SpeedPage(snapshot: snapshot, unit: unit, source: model.source, isOverLimit: model.isOverSpeedLimit)
        case .lean:
            LeanPage(snapshot: snapshot)
        case .totals:
            TotalsPage(snapshot: snapshot, unit: unit)
        case .terrain:
            TerrainPage(snapshot: snapshot, unit: unit)
        }
    }
}

// MARK: - Pages

/// The speed inside a ring that fills up with it, the top speed marked on the ring.
private struct SpeedPage: View {
    let snapshot: RideSnapshot
    let unit: SpeedUnit
    let source: WatchRideModel.Source?
    let isOverLimit: Bool
    @AppStorage(WatchSettings.speedAlertKey) private var speedAlert = false
    @AppStorage(WatchSettings.speedLimitKey) private var speedLimit = WatchSettings.defaultSpeedLimit

    var body: some View {
        let scale = unit.gaugeScale
        ZStack {
            SpeedRing(
                fraction: unit.speed(snapshot.speed) / scale,
                maxFraction: unit.speed(snapshot.maxSpeed) / scale,
                limitFraction: speedAlert ? unit.speed(speedLimit) / scale : nil
            )
            VStack(spacing: -4) {
                Text(Format.speed(snapshot.speed, unit))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(isOverLimit ? .red : .primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if snapshot.isPaused {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.yellow)
                } else {
                    Text(unit.speedLabel)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            SourceBadge(source: source)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.easeOut(duration: 0.4), value: snapshot.speed)
    }
}

/// A 270° ring open at the bottom, green at low speed and red near the top of the scale.
private struct SpeedRing: View {
    let fraction: Double
    let maxFraction: Double
    /// Where the speed alert fires, marked on the ring.
    let limitFraction: Double?

    private static let span = 0.75
    private static let lineWidth = 12.0

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let maxMark = min(max(maxFraction, 0), 1)
        ZStack {
            ZStack {
                arc(to: 1)
                    .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                arc(to: clamped)
                    .stroke(
                        AngularGradient(colors: [.green, .yellow, .orange, .red], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * Self.span)),
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                    )
            }
            // Turned so the opening faces down: the ring starts at the bottom left.
            .rotationEffect(.degrees(135))
            if let limitFraction, limitFraction > 0, limitFraction <= 1 {
                Capsule()
                    .fill(.red)
                    .frame(width: 4, height: Self.lineWidth + 8)
                    .rotationEffect(.degrees(135 + 360 * Self.span * limitFraction + 90))
                    .modifier(RingPosition(fraction: limitFraction, span: Self.span))
            }
            if maxMark > 0 {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .offset(y: -1)
                    .modifier(RingPosition(fraction: maxMark, span: Self.span))
            }
        }
        .padding(Self.lineWidth / 2)
    }

    /// Drawn from 0 then turned into place, so the gradient starts where the ring does.
    private func arc(to fraction: Double) -> some Shape {
        RingArc(fraction: fraction * Self.span)
    }
}

private struct RingArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: min(rect.width, rect.height) / 2,
                startAngle: .degrees(0),
                endAngle: .degrees(360 * fraction),
                clockwise: false
            )
        }
    }
}

/// Places a mark on the ring, `fraction` of the way along it.
private struct RingPosition: ViewModifier {
    let fraction: Double
    let span: Double

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let angle = Angle.degrees(135 + 360 * span * fraction).radians
            content
                .position(
                    x: proxy.size.width / 2 + radius * cos(angle),
                    y: proxy.size.height / 2 + radius * sin(angle)
                )
        }
    }
}

/// A half dial with the bike's silhouette tilting, and the deepest lean on each side.
private struct LeanPage: View {
    let snapshot: RideSnapshot

    private static let range = 60.0

    var body: some View {
        VStack(spacing: 2) {
            MetricLabel("INCLINAISON", color: .blue)
                .frame(maxWidth: .infinity, alignment: .leading)
            LeanDial(angle: snapshot.leanAngle, maxLeft: snapshot.maxLeanLeft, maxRight: snapshot.maxLeanRight, range: Self.range)
                .frame(maxHeight: .infinity)
            HStack(alignment: .lastTextBaseline) {
                Metric(label: "MAX G", value: Format.lean(snapshot.maxLeanLeft), color: .blue, size: 24)
                Spacer(minLength: 0)
                Text(Format.lean(snapshot.leanAngle))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Metric(label: "MAX D", value: Format.lean(snapshot.maxLeanRight), color: .blue, size: 24, alignment: .trailing)
            }
        }
        .animation(.easeOut(duration: 0.3), value: snapshot.leanAngle)
    }
}

private struct LeanDial: View {
    let angle: Double
    let maxLeft: Double
    let maxRight: Double
    let range: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width / 2, size.height) - 6
            let center = CGPoint(x: size.width / 2, y: size.height - 2)
            func point(_ degrees: Double, _ distance: Double) -> CGPoint {
                // 0° points up; left lean (negative) to the left.
                let radians = (degrees / range * 90 - 90) * .pi / 180
                return CGPoint(x: center.x + distance * cos(radians), y: center.y + distance * sin(radians))
            }

            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            context.stroke(track, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 6, lineCap: .round))

            for tick in stride(from: -range, through: range, by: 15) {
                var mark = Path()
                mark.move(to: point(tick, radius - 10))
                mark.addLine(to: point(tick, radius - (tick == 0 ? 18 : 14)))
                context.stroke(mark, with: .color(.white.opacity(0.4)), lineWidth: 2)
            }

            for peak in [-maxLeft, maxRight] where peak != 0 {
                let clamped = min(max(peak, -range), range)
                let dot = Path(ellipseIn: CGRect(origin: point(clamped, radius), size: .zero).insetBy(dx: -4, dy: -4))
                context.fill(dot, with: .color(.blue))
            }

            let clamped = min(max(angle, -range), range)
            var needle = Path()
            needle.move(to: point(clamped, radius * 0.35))
            needle.addLine(to: point(clamped, radius - 4))
            context.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}

/// The ride so far: time on top, as in the Workout app, then distance and speeds.
private struct TotalsPage: View {
    let snapshot: RideSnapshot
    let unit: SpeedUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                MetricLabel("DURÉE", color: .yellow)
                ElapsedTime(snapshot: snapshot)
            }
            Metric(label: "DISTANCE", value: String(format: "%.2f", unit.distance(snapshot.distance)), unit: unit.distanceLabel, color: .cyan, size: 34)
            HStack(alignment: .top) {
                Metric(label: "MOYENNE", value: Format.speed(snapshot.averageSpeed, unit), unit: unit.speedLabel, color: .green, size: 30)
                Spacer(minLength: 0)
                Metric(label: "MAX", value: Format.speed(snapshot.maxSpeed, unit), unit: unit.speedLabel, color: .red, size: 30, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Where the bike is: height and heading, with a compass needle.
private struct TerrainPage: View {
    let snapshot: RideSnapshot
    let unit: SpeedUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Metric(label: "ALTITUDE", value: snapshot.altitude.map { _ in Format.altitude(snapshot.altitude, unit) }, color: .green, size: 38)
            HStack(alignment: .center) {
                Metric(label: "CAP", value: snapshot.course.map { _ in Format.course(snapshot.course) }, color: .orange, size: 38)
                Spacer(minLength: 0)
                if let course = snapshot.course {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.orange)
                        .rotationEffect(.degrees(course))
                        .animation(.easeOut(duration: 0.4), value: course)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Always on

/// Wrist down: the one figure that matters, large and still, the way the system dims Workout.
private struct AlwaysOnView: View {
    @Environment(WatchRideModel.self) private var model

    var body: some View {
        let snapshot = model.snapshot
        let unit = model.unit
        VStack(spacing: 4) {
            if let state = model.guidance?.state {
                GuidanceArrow(state: state, course: snapshot.course)
                    .font(.system(size: 64, weight: .bold))
                    .frame(maxHeight: .infinity)
                Text(state.hasArrived ? "Arrivé" : Format.shortDistance(state.distanceToManeuver, unit))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                BigNumber(value: Format.speed(snapshot.speed, unit), unit: unit.speedLabel, size: 24)
                    .foregroundStyle(.secondary)
            } else {
                BigNumber(value: Format.speed(snapshot.speed, unit), unit: unit.speedLabel, size: 80)
                    .foregroundStyle(model.isOverSpeedLimit ? .red : .primary)
                    .frame(maxHeight: .infinity)
                ElapsedTime(snapshot: snapshot, size: 28)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal)
    }
}

// MARK: - Building blocks

private extension SpeedUnit {
    /// The top of the speed ring, in the display unit.
    var gaugeScale: Double {
        switch self {
        case .kilometersPerHour: 200
        case .milesPerHour: 130
        }
    }
}

/// The Workout app's labels: small capitals in the metric's color.
private struct MetricLabel: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(color)
    }
}

/// A label over a large figure. A missing figure shows as a dimmed placeholder rather than a dash.
private struct Metric: View {
    let label: String
    let value: String?
    var unit = ""
    let color: Color
    let size: CGFloat
    var alignment = HorizontalAlignment.leading

    var body: some View {
        VStack(alignment: alignment, spacing: -2) {
            MetricLabel(label, color: color)
            if let value {
                BigNumber(value: value, unit: unit, size: size)
            } else {
                Text("--")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// The Workout app's type: large rounded digits, a small unit beside them.
struct BigNumber: View {
    let value: String
    let unit: String
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: max(size * 0.38, 14), weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// Counts up on its own, as a system timer text: no redraw needed every second. Frozen while paused.
private struct ElapsedTime: View {
    let snapshot: RideSnapshot
    var size: CGFloat = 40

    var body: some View {
        Group {
            if snapshot.isPaused {
                Label(Format.duration(snapshot.elapsed(at: .now)), systemImage: "pause.fill")
            } else if let start = snapshot.timerStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text("0:00")
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.yellow)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

private struct SourceBadge: View {
    let source: WatchRideModel.Source?

    var body: some View {
        switch source {
        case .phone:
            Image(systemName: "iphone")
                .foregroundStyle(.green)
                .font(.footnote.weight(.semibold))
                .accessibilityLabel("Vitesse de l'iPhone")
        case .watch:
            Image(systemName: "location.fill")
                .foregroundStyle(.secondary)
                .font(.footnote.weight(.semibold))
                .accessibilityLabel("GPS de la montre")
        case nil:
            EmptyView()
        }
    }
}
