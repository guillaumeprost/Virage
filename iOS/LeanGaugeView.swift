import SwiftUI

/// Half-dial showing the current lean, with the ride's maximum on each side.
struct LeanGaugeView: View {
    let snapshot: RideSnapshot
    var dialHeight: CGFloat = 110
    @Environment(\.dashboardStyle) private var style

    /// The dial spans ±60°, beyond what a road bike reaches.
    private static let range = 60.0

    var body: some View {
        VStack(spacing: 4) {
            dial
            HStack(alignment: .lastTextBaseline) {
                peak("G", snapshot.maxLeanLeft)
                Spacer()
                Text(Format.lean(snapshot.leanAngle))
                    .font(style.figureFont(.title.weight(.bold), size: 30, relativeTo: .title))
                    .styledDigits(style)
                    .monospacedDigit()
                Spacer()
                peak("D", snapshot.maxLeanRight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Inclinaison \(Format.lean(snapshot.leanAngle))")
    }

    private var dial: some View {
        Canvas { context, size in
            let radius = min(size.width / 2, size.height) - 8
            let center = CGPoint(x: size.width / 2, y: size.height - 4)

            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 10, lineCap: style == .sport ? .butt : .round))
            if style == .sport, snapshot.leanAngle != 0 {
                // The lean filled from the top, like a bar: read at a glance.
                var lean = Path()
                lean.addArc(center: center, radius: radius, startAngle: .degrees(270), endAngle: Self.dialAngle(snapshot.leanAngle), clockwise: snapshot.leanAngle < 0)
                context.stroke(lean, with: .color(DashboardStyle.racingRed), style: StrokeStyle(lineWidth: 10))
            }

            for tick in [-45.0, -30, 0, 30, 45] {
                let angle = Self.dialAngle(tick)
                var mark = Path()
                mark.move(to: Self.point(center, radius - 14, angle))
                mark.addLine(to: Self.point(center, radius - 24, angle))
                context.stroke(mark, with: .color(.secondary), lineWidth: 2)
            }

            for peak in [-snapshot.maxLeanLeft, snapshot.maxLeanRight] where peak != 0 {
                let position = Self.point(center, radius, Self.dialAngle(peak))
                context.fill(Path(ellipseIn: CGRect(x: position.x - 6, y: position.y - 6, width: 12, height: 12)), with: .color(.accentColor))
            }

            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: Self.point(center, radius - 6, Self.dialAngle(snapshot.leanAngle)))
            let needleColor = style == .retro ? DashboardStyle.ink : Color.primary
            context.stroke(needle, with: .color(needleColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(style == .retro ? Color.secondary : .primary))
        }
        .frame(height: dialHeight)
    }

    private func peak(_ side: String, _ degrees: Double) -> some View {
        VStack(spacing: 2) {
            Text("Max \(side)")
                .font(style.labelFont(.caption2.weight(.semibold), size: 12, relativeTo: .caption2))
                .foregroundStyle(.secondary)
            Text(Format.lean(degrees))
                .font(style.figureFont(.subheadline.weight(.bold), size: 16, relativeTo: .subheadline))
                .styledDigits(style)
                .foregroundStyle(.tint)
                .monospacedDigit()
        }
    }

    /// 0° lean points straight up; right lean turns the needle clockwise.
    private static func dialAngle(_ lean: Double) -> Angle {
        let clamped = min(max(lean, -range), range)
        return .degrees(270 + clamped / range * 90)
    }

    private static func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
    }
}
