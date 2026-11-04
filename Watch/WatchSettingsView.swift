import SwiftUI

struct WatchSettingsView: View {
    @Environment(WatchRideModel.self) private var model
    @AppStorage(WatchSettings.guidanceHapticsKey) private var guidanceHaptics = true
    @AppStorage(WatchSettings.speedAlertKey) private var speedAlert = false
    @AppStorage(WatchSettings.speedLimitKey) private var speedLimit = WatchSettings.defaultSpeedLimit

    var body: some View {
        List {
            Section {
                Toggle("Vibrations", isOn: $guidanceHaptics)
            } header: {
                Text("Guidage")
            } footer: {
                Text("Une vibration à 300 m du virage, deux au moment de tourner. Le motif diffère à gauche et à droite.")
            }

            Section {
                Toggle("Alerte de vitesse", isOn: $speedAlert)
                if speedAlert {
                    Picker("Limite", selection: limitInDisplayUnit) {
                        ForEach(Array(stride(from: 30, through: 200, by: 10)), id: \.self) { value in
                            Text("\(value) \(model.unit.speedLabel)").tag(value)
                        }
                    }
                }
            } footer: {
                Text("La montre vibre en passant la limite, puis chaque minute tant que tu restes au-dessus.")
            }
        }
        .navigationTitle("Réglages")
    }

    /// Stored in meters per second, so changing units on the iPhone keeps the same limit.
    private var limitInDisplayUnit: Binding<Int> {
        Binding {
            Int((model.unit.speed(speedLimit) / 10).rounded()) * 10
        } set: { value in
            speedLimit = Double(value) / model.unit.speed(1)
        }
    }
}
