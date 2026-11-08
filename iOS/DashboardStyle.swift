import SwiftUI

/// The look of the dashboard: the same figures and controls, dressed for the bike.
enum DashboardStyle: String, CaseIterable, Identifiable {
    /// Native iOS: large rounded digits, light or dark with the system.
    case classic
    /// Ink and paper, or cream on black: figures in a slab serif and labels in engraved capitals, as on a café
    /// racer's clocks.
    case retro
    /// A segmented speed bar like a rev counter over big italic digits, racing red.
    case sport

    static let storageKey = "dashboardStyle"

    var id: Self { self }

    var label: String {
        switch self {
        case .classic: "Classique"
        case .retro: "Rétro"
        case .sport: "Sport"
        }
    }

    // The colors are built once: the dashboard redraws 25 times a second, and a new dynamic color each time
    // would read to SwiftUI as a change.

    /// Retro's page: warm paper by day, near black by night.
    private static let paper = Color(light: Color(red: 0.95, green: 0.93, blue: 0.89), dark: Color(red: 0.086, green: 0.094, blue: 0.102))
    private static let sportBackground = Color(light: Color(red: 0.955, green: 0.96, blue: 0.97), dark: Color(red: 0.047, green: 0.051, blue: 0.059))
    private static let retroOutline = Color(light: Color.black.opacity(0.18), dark: Color(red: 0.2, green: 0.21, blue: 0.23))
    private static let sportOutline = Color(light: Color.black.opacity(0.14), dark: Color(red: 0.13, green: 0.145, blue: 0.165))

    var background: Color {
        switch self {
        case .classic: Color(.systemBackground)
        case .retro: Self.paper
        case .sport: Self.sportBackground
        }
    }

    /// The figures in Retro: black ink on paper, cream on black.
    static let ink = Color(light: Color(red: 0.11, green: 0.105, blue: 0.1), dark: Color(red: 0.925, green: 0.91, blue: 0.87))

    /// Buttons, toggles and highlights across the app.
    var tint: Color? {
        switch self {
        case .classic: nil
        case .retro: Self.ink
        case .sport: Self.racingRed
        }
    }

    /// Text on a control filled with the tint.
    var onTint: Color {
        switch self {
        case .classic, .sport: .white
        case .retro: Self.paper
        }
    }

    /// Hairlines around tiles and badges.
    var outline: Color {
        switch self {
        case .classic: .clear
        case .retro: Self.retroOutline
        case .sport: Self.sportOutline
        }
    }

    /// Digits in Sport lean forward, like the numbers on a race fairing.
    var leansDigits: Bool { self == .sport }

    /// The font of a figure: Rockwell in Retro, the given system font otherwise. Scales with Dynamic Type.
    func figureFont(_ system: Font, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        self == .retro ? .custom("Rockwell-Bold", size: size, relativeTo: textStyle) : system
    }

    /// The font of a label: engraved capitals in Retro, the given system font otherwise.
    func labelFont(_ system: Font, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        self == .retro ? .custom("Copperplate-Bold", size: size, relativeTo: textStyle) : system
    }

    static let racingRed = Color(red: 0.9, green: 0.22, blue: 0.23)
}

extension Color {
    /// One color by day, another by night, following the interface style.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

private struct DashboardStyleKey: EnvironmentKey {
    static let defaultValue = DashboardStyle.classic
}

extension EnvironmentValues {
    var dashboardStyle: DashboardStyle {
        get { self[DashboardStyleKey.self] }
        set { self[DashboardStyleKey.self] = newValue }
    }
}

extension View {
    /// Italic in Sport, upright otherwise.
    func styledDigits(_ style: DashboardStyle) -> some View {
        italic(style.leansDigits)
    }
}

// MARK: - Speed

/// The speed as large as its slot allows, between two sizes: the layouts give it whatever height is left.
struct FittedSpeedDisplay: View {
    let snapshot: RideSnapshot
    let unit: SpeedUnit
    let sizes: ClosedRange<CGFloat>
    @Environment(\.dashboardStyle) private var style

    var body: some View {
        GeometryReader { slot in
            SpeedDisplay(snapshot: snapshot, unit: unit, size: min(max(slot.size.height / heightRatio, sizes.lowerBound), sizes.upperBound))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The block's height for each point of `SpeedDisplay`'s size: the digits and the unit beneath.
    private var heightRatio: CGFloat {
        switch style {
        case .classic: 1.12
        case .retro: 1.08
        case .sport: 1.3
        }
    }
}

/// The speed as each style shows it.
struct SpeedDisplay: View {
    let snapshot: RideSnapshot
    let unit: SpeedUnit
    /// The height of the digits in the classic style; the other styles scale from it.
    let size: CGFloat
    @Environment(\.dashboardStyle) private var style

    var body: some View {
        switch style {
        case .classic: classic
        case .retro: retro
        case .sport: SportSpeed(snapshot: snapshot, unit: unit, size: size)
        }
    }

    private var classic: some View {
        VStack(spacing: 0) {
            Text(Format.speed(snapshot.speed, unit))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .contentTransition(.numericText(value: snapshot.speed))
                .animation(.snappy, value: Int(unit.speed(snapshot.speed)))
                .foregroundStyle(snapshot.isPaused ? .secondary : .primary)
            PausedOrUnit(snapshot: snapshot, unit: unit)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    /// Cream figures in a slab serif, the unit in engraved capitals below.
    private var retro: some View {
        // Rockwell's line keeps room for descenders figures never use: the unit tucks under the digits.
        VStack(spacing: -size * 0.22) {
            Text(Format.speed(snapshot.speed, unit))
                .font(.custom("Rockwell-Bold", fixedSize: size))
                .monospacedDigit()
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .contentTransition(.numericText(value: snapshot.speed))
                .animation(.snappy, value: Int(unit.speed(snapshot.speed)))
                .foregroundStyle(snapshot.isPaused ? Color.secondary : DashboardStyle.ink)
            Group {
                if snapshot.isPaused {
                    Text("En pause")
                } else {
                    Text(unit.speedLabel)
                }
            }
            .font(.custom("Copperplate-Bold", size: max(size * 0.12, 15), relativeTo: .title2))
            .textCase(.uppercase)
            .tracking(3)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PausedOrUnit: View {
    let snapshot: RideSnapshot
    let unit: SpeedUnit

    var body: some View {
        Group {
            if snapshot.isPaused {
                Label("En pause", systemImage: "pause.fill")
            } else {
                Text(unit.speedLabel)
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// The top of the scale, per unit: a road bike's dial.
private func dialMaximum(_ unit: SpeedUnit) -> Double {
    unit == .kilometersPerHour ? 200 : 120
}

/// A segmented bar like a rev counter over big italic digits.
struct SportSpeed: View {
    let snapshot: RideSnapshot
    let unit: SpeedUnit
    let size: CGFloat

    static let segments = 14

    var body: some View {
        let lit = Int((unit.speed(snapshot.speed) / dialMaximum(unit) * Double(Self.segments)).rounded(.up))
        VStack(spacing: size * 0.06) {
            HStack(spacing: max(size * 0.012, 2)) {
                ForEach(0..<Self.segments, id: \.self) { index in
                    Rectangle()
                        .fill(index < lit ? Self.color(index) : Color.primary.opacity(0.1))
                }
            }
            .frame(height: min(max(size * 0.08, 8), 18))
            .animation(.snappy, value: lit)
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: size * 0.04) {
                Text(Format.speed(snapshot.speed, unit))
                    .font(.system(size: size, weight: .heavy))
                    .italic()
                    .monospacedDigit()
                    .tracking(-size * 0.03)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: snapshot.speed))
                    .animation(.snappy, value: Int(unit.speed(snapshot.speed)))
                    .foregroundStyle(snapshot.isPaused ? .secondary : .primary)
                PausedOrUnit(snapshot: snapshot, unit: unit)
                    .font(.system(size: max(size * 0.12, 13), weight: .semibold))
                    .italic()
                    .labelStyle(.iconOnly)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Green, then yellow past 60 % of the scale, red past 85 %.
    private static func color(_ index: Int) -> Color {
        let share = Double(index + 1) / Double(segments)
        if share > 0.85 { return DashboardStyle.racingRed }
        if share > 0.6 { return Color(red: 0.91, green: 0.88, blue: 0.23) }
        return Color(red: 0.18, green: 0.83, blue: 0.42)
    }
}
