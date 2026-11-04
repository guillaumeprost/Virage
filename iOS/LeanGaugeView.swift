import SwiftUI

/// Half-dial showing the current lean, with the ride's maximum on each side.
struct LeanGaugeView: View {
    let snapshot: RideSnapshot
    var dialHeight: CGFloat = 110

    /// The dial spans ±60°, beyond what a road bike reaches.
    private static let range = 60.0

    var body: some View {
        VStack(spacing: 4) {
            dial
            HStack(alignment: .lastTextBaseline) {
                peak("G", snapshot.maxLeanLeft)
                Spacer()
                Text(Format.lean(snapshot.leanAngle))
                    .font(.title.weight(.bold))
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
            context.stroke(track, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

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
            context.stroke(needle, with: .color(.primary), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.primary))
        }
        .frame(height: dialHeight)
    }

    private func peak(_ side: String, _ degrees: Double) -> some View {
        VStack(spacing: 2) {
            Text("Max \(side)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Format.lean(degrees))
                .font(.subheadline.weight(.bold))
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
