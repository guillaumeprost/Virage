import CoreLocation
import SwiftData
import UIKit

/// Owns the sensors on the iPhone: GPS for speed and track, gyroscope for lean.
///
/// The speedometer runs whenever the app is in the foreground. A ride adds statistics, background tracking
/// and the saved trip on top of it.
@MainActor
@Observable
final class RideEngine: NSObject {
    private(set) var snapshot = RideSnapshot()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let leanMeter = LeanMeter()
    @ObservationIgnored private let watchLauncher = WatchWorkoutLauncher()
    @ObservationIgnored private let modelContainer: ModelContainer
    @ObservationIgnored private let connectivity: PhoneConnectivity
    @ObservationIgnored private let navigation: NavigationController
    @ObservationIgnored private let liveActivity = RideLiveActivityController()
    @ObservationIgnored private var stats = RideStats()
    @ObservationIgnored private var track: [TrackPoint] = []
    @ObservationIgnored private var isUpdating = false
    @ObservationIgnored private var wantsUpdates = false
    /// Stopped at a light, no sensor changes and nothing would be sent: the Watch would take the silence for
    /// a lost iPhone and switch to its own GPS.
    @ObservationIgnored private var heartbeat: Timer?

    init(modelContainer: ModelContainer, connectivity: PhoneConnectivity, navigation: NavigationController) {
        self.modelContainer = modelContainer
        self.connectivity = connectivity
        self.navigation = navigation
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .otherNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.headingFilter = 2
        authorization = locationManager.authorizationStatus
        connectivity.onCommand = { [weak self] command in
            switch command {
            case .start: self?.startRide(fromWatch: true)
            case .stop: self?.stopRide()
            case .stopNavigation: self?.navigation.stop()
            case .pause: self?.setPaused(true)
            case .resume: self?.setPaused(false)
            case .skipStop: self?.navigation.skipNextStop()
            case .requestRoute: break
            }
        }
        connectivity.onRoute = { [weak self] route in
            guard let self else { return }
            guard let route else {
                navigation.stop()
                return
            }
            // A destination chosen on the wrist: the iPhone takes over routing and rides along.
            navigation.start(route, from: snapshot.position)
            startRide(fromWatch: true)
        }
        connectivity.onTrip = { [weak self] trip in
            self?.saveWatchTrip(trip)
        }
    }

    var isLocationDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Sensors run in the foreground, and in the background only during a ride.
    func setForeground(_ isForeground: Bool) {
        if isForeground {
            wantsUpdates = true
            startUpdates()
        } else if !snapshot.isRiding {
            wantsUpdates = false
            stopUpdates()
        }
    }

    func startRide(fromWatch: Bool = false) {
        guard !snapshot.isRiding else { return }
        stats.start(at: .now)
        track = []
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        UIApplication.shared.isIdleTimerDisabled = true
        wantsUpdates = true
        startUpdates()
        if !fromWatch {
            watchLauncher.launch()
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        publish(force: true)
        liveActivity.start(state: activityState())
    }

    func stopRide() {
        guard snapshot.isRiding else { return }
        stats.stop()
        navigation.stop()
        liveActivity.end()
        heartbeat?.invalidate()
        heartbeat = nil
        locationManager.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false
        saveTrip()
        if UIApplication.shared.applicationState == .background {
            wantsUpdates = false
            stopUpdates()
        }
        publish(force: true)
    }

    /// The ride stays open, with the GPS and the guidance still running, but its figures wait.
    func setPaused(_ paused: Bool) {
        guard snapshot.isRiding, paused != snapshot.isPaused else { return }
        if paused {
            stats.pause(at: .now)
        } else {
            stats.unpause(at: .now)
        }
        publish(force: true)
    }

    private func startUpdates() {
        guard wantsUpdates, !isUpdating else { return }
        switch authorization {
        case .notDetermined:
            // Resumes from the authorization callback.
            locationManager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            return
        default:
            break
        }
        isUpdating = true
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        leanMeter.start { [weak self] yawRate in
            self?.handleYawRate(yawRate)
        }
    }

    private func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        leanMeter.stop()
    }

    private func handle(_ location: CLLocation) {
        guard stats.ingest(location) else { return }
        if snapshot.isRiding, !snapshot.isPaused, track.last.map({ location.timestamp.timeIntervalSince($0.timestamp) >= 1 }) ?? true {
            track.append(TrackPoint(location))
        }
        if let position = stats.snapshot.position {
            navigation.update(position)
        }
        publish()
    }

    private func handleYawRate(_ yawRate: Double) {
        stats.recordLean(LeanAngle.degrees(speed: stats.snapshot.speed, yawRate: yawRate))
        publish()
    }

    private func publish(force: Bool = false) {
        snapshot = stats.snapshot
        connectivity.send(snapshot, force: force)
        if snapshot.isRiding {
            liveActivity.update(activityState())
        }
    }

    /// What the lock screen shows: the same figures as the dashboard, already formatted.
    private func activityState() -> RideActivityAttributes.ContentState {
        let unit = SpeedUnit.current
        let guidance = navigation.state.map { state in
            let symbol: String
            let instruction: String
            if state.hasArrived {
                symbol = Maneuver.arrive.symbolName
                instruction = "Arrivé à \(state.destinationName)"
            } else if state.isOffRoute, state.followsTrack {
                symbol = "point.topleft.down.to.point.bottomright.curvepath"
                instruction = "Hors de la trace : rejoins-la"
            } else if state.isOffRoute || navigation.isRerouting {
                symbol = "arrow.triangle.2.circlepath"
                instruction = "Recalcul de l'itinéraire…"
            } else if state.mode == .compass {
                // The arrow would have to turn with the bike; the lock screen updates too rarely for that.
                symbol = "safari"
                instruction = state.destinationName
            } else {
                symbol = state.maneuver.symbolName
                instruction = state.instruction
            }
            return RideActivityAttributes.Guidance(
                symbol: symbol,
                distance: state.hasArrived ? "" : Format.shortDistance(state.distanceToManeuver, unit),
                instruction: instruction
            )
        }
        return RideActivityAttributes.ContentState(
            speed: Format.speed(snapshot.speed, unit),
            speedUnit: unit.speedLabel,
            distance: Format.distance(snapshot.distance, unit),
            guidance: guidance,
            timerStart: snapshot.timerStart ?? .now,
            pausedTime: snapshot.isPaused ? Format.duration(snapshot.elapsed(at: .now)) : nil
        )
    }

    /// A ride the Watch recorded on its own GPS, the iPhone not taking part.
    private func saveWatchTrip(_ trip: WatchTrip) {
        guard trip.snapshot.distance > 0, trip.track.count >= 2 else { return }
        let context = modelContainer.mainContext
        let start = trip.snapshot.startDate ?? trip.track.first?.timestamp ?? trip.endDate
        // A trip sent twice (a retried transfer) is saved once.
        let existing = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.startDate == start }))) ?? []
        guard existing.isEmpty else { return }
        context.insert(Trip(snapshot: trip.snapshot, endDate: trip.endDate, track: trip.track))
        try? context.save()
    }

    private func saveTrip() {
        guard snapshot.distance > 0, track.count >= 2 else { return }
        let context = modelContainer.mainContext
        context.insert(Trip(snapshot: snapshot, endDate: .now, track: track))
        try? context.save()
        track = []
    }
}

extension RideEngine: CLLocationManagerDelegate {
    // The manager was created on the main thread, so it calls back on the main thread.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            startUpdates()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            locations.forEach(handle)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        MainActor.assumeIsolated {
            stats.updateHeading(degrees)
            publish()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
