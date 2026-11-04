import SwiftUI

struct SettingsView: View {
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Apparence", selection: $appearance) {
                        Text("Système").tag(Appearance.system)
                        Text("Clair").tag(Appearance.light)
                        Text("Sombre").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Apparence")
                } footer: {
                    Text("« Système » suit le réglage de l'iPhone, y compris le passage automatique au mode sombre le soir.")
                }
                Section("Unités") {
                    Picker("Vitesse", selection: $unit) {
                        ForEach(SpeedUnit.allCases) { unit in
                            Text(unit.speedLabel).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("L'inclinaison est calculée à partir de la vitesse et de la rotation de la moto dans les virages. Elle fonctionne quelle que soit la fixation du téléphone, mais seulement au-dessus de 10 km/h.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Inclinaison")
                }
                Section {
                    Text("Démarre un trajet sur l'iPhone ou sur la montre : l'autre suit. Si l'iPhone n'est pas joignable, la montre utilise son propre GPS et t'envoie le trajet ensuite. Tes favoris et destinations récentes sont aussi disponibles sur la montre. Les vibrations et l'alerte de vitesse se règlent dans l'app de la montre.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Apple Watch")
                }
            }
            .navigationTitle("Réglages")
        }
    }
}
