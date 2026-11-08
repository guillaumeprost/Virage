import SwiftUI

struct SettingsView: View {
    @AppStorage(SpeedUnit.storageKey) private var unit = SpeedUnit.kilometersPerHour
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(DashboardStyle.storageKey) private var style = DashboardStyle.classic
    @AppStorage(FuelSettings.enabledKey) private var tracksFuel = false
    @AppStorage(FuelSettings.rangeKey) private var fuelRange = FuelSettings.defaultRangeKilometers
    @AppStorage(FuelSettings.reserveKey) private var fuelReserve = FuelSettings.defaultReserveKilometers
    @Environment(RideEngine.self) private var engine

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Style du compteur", selection: $style) {
                        ForEach(DashboardStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Apparence", selection: $appearance) {
                        Text("Système").tag(Appearance.system)
                        Text("Clair").tag(Appearance.light)
                        Text("Sombre").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Apparence")
                } footer: {
                    switch style {
                    case .classic:
                        Text("Le compteur natif d'iOS. « Système » suit le réglage de l'iPhone, y compris le passage automatique au mode sombre le soir.")
                    case .retro:
                        Text("Chiffres à empattements et libellés en capitales gravées, comme les compteurs d'un café racer : encre sur papier en clair, crème sur noir en sombre. « Système » suit le réglage de l'iPhone.")
                    case .sport:
                        Text("Une barre de vitesse façon compte-tours et de grands chiffres penchés, en clair comme en sombre. « Système » suit le réglage de l'iPhone.")
                    }
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
                    LabeledContent("Depuis le plein", value: Format.distance(engine.sinceRefuel, unit))
                        .monospacedDigit()
                    Button("Plein fait", systemImage: "fuelpump.fill") {
                        engine.refuel()
                    }
                    Toggle("Suivre l'autonomie", isOn: $tracksFuel)
                    if tracksFuel {
                        Stepper(value: $fuelRange, in: 50...800, step: 10) {
                            LabeledContent("Avec un plein", value: "\(Int(fuelRange)) km")
                        }
                        Stepper(value: $fuelReserve, in: 10...150, step: 5) {
                            LabeledContent("Prévenir à", value: "\(Int(fuelReserve)) km")
                        }
                    }
                } header: {
                    Text("Carburant")
                } footer: {
                    if tracksFuel, let fuel = engine.fuel {
                        Text("Il reste environ \(Int(fuel.remaining / 1_000)) km sur ce plein, d'après les trajets enregistrés sur l'iPhone et la montre. Touche « Plein fait » à la pompe.")
                    } else {
                        Text("Le compteur repart de zéro à chaque « Plein fait ». Avec le suivi de l'autonomie, Virage te prévient aussi à l'approche de la réserve et trouve les stations sur ta route.")
                    }
                }
                .onChange(of: tracksFuel) { engine.reloadFuel() }
                .onChange(of: fuelRange) { engine.reloadFuel() }
                .onChange(of: fuelReserve) { engine.reloadFuel() }
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
