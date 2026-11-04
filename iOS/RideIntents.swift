import AppIntents

// Actions for the Action button, Siri and Shortcuts. They act on the ride already running in the app, which
// background location keeps alive: no need to bring it to the screen.

struct SkipStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Passer l'étape"
    static let description = IntentDescription("Abandonne la prochaine étape et recalcule l'itinéraire vers la suivante.")

    @Dependency private var navigation: NavigationController

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let stop = navigation.nextStop else {
            return .result(dialog: "Aucune étape à passer.")
        }
        navigation.skipNextStop()
        return .result(dialog: "Étape \(stop.name) passée.")
    }
}

struct TogglePauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause ou reprise du trajet"
    static let description = IntentDescription("Met le trajet en cours en pause, ou le reprend.")

    @Dependency private var engine: RideEngine

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard engine.snapshot.isRiding else {
            return .result(dialog: "Aucun trajet en cours.")
        }
        let pausing = !engine.snapshot.isPaused
        engine.setPaused(pausing)
        return .result(dialog: pausing ? "Trajet en pause." : "Trajet repris.")
    }
}

struct StartRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Démarrer un trajet"
    static let description = IntentDescription("Ouvre Virage et démarre l'enregistrement d'un trajet.")
    /// The GPS may only start in the background once a ride is under way.
    static let openAppWhenRun = true

    @Dependency private var engine: RideEngine

    @MainActor
    func perform() async throws -> some IntentResult {
        engine.startRide()
        return .result()
    }
}

struct RefuelIntent: AppIntent {
    static let title: LocalizedStringResource = "Plein fait"
    static let description = IntentDescription("Remet l'autonomie du réservoir à son maximum.")

    @Dependency private var engine: RideEngine

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard engine.fuel != nil else {
            return .result(dialog: "Active le suivi de l'autonomie dans les réglages de Virage.")
        }
        engine.refuel()
        return .result(dialog: "Plein noté.")
    }
}

/// Offered without any setup: in Shortcuts, to Siri, and for the Action button.
struct VirageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SkipStopIntent(),
            phrases: ["Passe l'étape dans \(.applicationName)", "Étape suivante dans \(.applicationName)"],
            shortTitle: "Passer l'étape",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: TogglePauseIntent(),
            phrases: ["Pause dans \(.applicationName)", "Reprends le trajet dans \(.applicationName)"],
            shortTitle: "Pause / reprise",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: StartRideIntent(),
            phrases: ["Démarre un trajet avec \(.applicationName)"],
            shortTitle: "Démarrer un trajet",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: RefuelIntent(),
            phrases: ["Plein fait dans \(.applicationName)"],
            shortTitle: "Plein fait",
            systemImageName: "fuelpump.fill"
        )
    }
}
