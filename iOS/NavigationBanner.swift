import SwiftUI

/// Next maneuver at the top of the dashboard, the same reading as on the Watch.
struct NavigationBanner: View {
    let state: GuidanceState
    let course: Double?
    let isRerouting: Bool
    /// Set while a stop lies ahead, to offer skipping it.
    var nextStop: Waypoint?
    var onSkipStop: () -> Void = {}
    let onStop: () -> Void

    @State private var isConfirmingSkip = false
    @State private var isConfirmingStop = false

    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                GuidanceArrow(state: state, course: course)
                    .font(.system(size: 44, weight: .bold))
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.shortDistance(state.distanceToManeuver, unit))
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    isConfirmingStop = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        // A glove-sized target, though the symbol stays small.
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Arrêter la navigation")
                .confirmationDialog("Arrêter la navigation ?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
                    Button("Arrêter la navigation", role: .destructive, action: onStop)
                } message: {
                    Text("Le trajet continue d'être enregistré.")
                }
            }

            // On its own row, the full width, far from the stop button: with gloves the two were easy to mix up.
            if let nextStop {
                Button {
                    isConfirmingSkip = true
                } label: {
                    Label("Passer l'étape \(nextStop.name)", systemImage: "forward.end.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Passer l'étape \(nextStop.name) ?", isPresented: $isConfirmingSkip, titleVisibility: .visible) {
                    Button("Passer l'étape", action: onSkipStop)
                } message: {
                    Text("L'itinéraire est recalculé vers la suite du trajet.")
                }
            }
        }
        .padding(12)
        // Opaque, so it stays readable whatever it ends up over during a layout change.
        .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 16))
        .background(Color(.systemBackground), in: .rect(cornerRadius: 16))
    }

    private var subtitle: String {
        if state.hasArrived {
            return "Arrivé à \(state.destinationName)"
        }
        if state.isOffRoute, state.followsTrack {
            return "Hors de la trace : rejoins-la"
        }
        if isRerouting || state.isOffRoute {
            return "Recalcul de l'itinéraire…"
        }
        let remaining = "\(Format.distance(state.remainingDistance, unit)) restants"
        return state.mode == .route ? "\(state.instruction) · \(remaining)" : "\(state.destinationName) · \(remaining)"
    }
}
