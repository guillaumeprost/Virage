import AppIntents

// On Apple Watch Ultra, Virage can be chosen as the Action button's workout: one press starts a ride, the Action
// and side buttons pressed together pause it and resume it, as in Workout.

enum RideStyle: String, AppEnum {
    case motorcycle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trajet"
    static let caseDisplayRepresentations: [RideStyle: DisplayRepresentation] = [
        .motorcycle: DisplayRepresentation(title: "Trajet à moto", image: .init(systemName: "gauge.with.dots.needle.67percent")),
    ]
}

struct StartRideWorkoutIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Démarrer un trajet"

    @Parameter(title: "Trajet")
    var workoutStyle: RideStyle

    static var suggestedWorkouts: [StartRideWorkoutIntent] {
        [StartRideWorkoutIntent(style: .motorcycle)]
    }

    var displayRepresentation: DisplayRepresentation {
        RideStyle.caseDisplayRepresentations[workoutStyle] ?? DisplayRepresentation(title: "Trajet à moto")
    }

    init() {
        workoutStyle = .motorcycle
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRideModel.shared.startRide()
        return .result()
    }
}

struct PauseRideIntent: PauseWorkoutIntent {
    static let title: LocalizedStringResource = "Mettre le trajet en pause"

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRideModel.shared.setPaused(true)
        return .result()
    }
}

struct ResumeRideIntent: ResumeWorkoutIntent {
    static let title: LocalizedStringResource = "Reprendre le trajet"

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRideModel.shared.setPaused(false)
        return .result()
    }
}

struct SkipStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Passer l'étape"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = WatchRideModel.shared
        guard let stop = model.nextStop else {
            return .result(dialog: "Aucune étape à passer.")
        }
        model.skipNextStop()
        return .result(dialog: "Étape \(stop.name) passée.")
    }
}

/// For Siri on the wrist, and the Shortcuts app on the Watch.
struct VirageWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SkipStopIntent(),
            phrases: ["Passe l'étape dans \(.applicationName)"],
            shortTitle: "Passer l'étape",
            systemImageName: "forward.end.fill"
        )
    }
}
