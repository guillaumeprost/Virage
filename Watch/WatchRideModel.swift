import CoreLocation
import HealthKit
import OSLog
import WatchConnectivity
import WatchKit

/// Shows the iPhone's ride while it is reachable, and falls back to the Watch's own GPS when it is not.
///
/// A workout session runs for the whole ride: without it the app is suspended as soon as the wrist drops.
@MainActor
@Observable
final class WatchRideModel: NSObject {
    static let shared = WatchRideModel()

    enum Source {
        case phone
        case watch
    }

    private(set) var snapshot = RideSnapshot()
    private(set) var source: Source?
    private(set) var unit = SpeedUnit.current
    private(set) var guidance: Guidance?
    private(set) var isRerouting = false
    /// Favorites and recents from the iPhone, kept for when it is out of reach.
    private(set) var places = WatchSettings.places
    private(set) var isOverSpeedLimit = false

    /// The iPhone sends twice a second; three seconds of silence means it is gone.
    static let phoneTimeout: TimeInterval = 3
    static let rerouteInterval: TimeInterval = 15

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var workout: HKWorkoutSession?
    @ObservationIgnored private var localStats = RideStats()
    @ObservationIgnored private var lastPhoneUpdate = Date.distantPast
    /// Whether the iPhone has recorded part of this ride, and so may end it.
    @ObservationIgnored private var phoneJoinedRide = false
    @ObservationIgnored private var sourceTimer: Timer?
    @ObservationIgnored private var isLocalGPSRunning = false
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private let widgets = RideWidgetPublisher()
    @ObservationIgnored private var speedAlert: SpeedAlert?
    /// Recorded on the Watch's GPS, for a ride the iPhone never took part in.
    @ObservationIgnored private var track: [TrackPoint] = []

    var isRiding: Bool { snapshot.isRiding }

    func activate() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .otherNavigation
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: nil) { _, _ in }
    }

    func startRide() {
        guard !isRiding else { return }
        send(.start)
        beginRide(startDate: .now)
    }

    func stopRide() {
        guard isRiding else { return }
        send(.stop)
        endRide()
    }

    /// A destination chosen on the wrist. The route is planned here, so it works without the iPhone; when the
    /// iPhone is in reach it gets the route too and takes over rerouting.
    func navigate(to place: SavedPlace, mode: NavigationMode, avoidsTolls: Bool) async throws {
        let route = switch mode {
        case .compass:
            RoutePlanner.compass(to: place.coordinate, named: place.name)
        case .route:
            try await planRoute(to: place, avoidsTolls: avoidsTolls)
        }
        setRoute(route)
        startRide()
        sendToPhone(route)
    }

    /// Apple Maps sometimes fails for a moment (a timeout, a road closure being updated): one retry spares the
    /// rider tapping again with gloves on.
    private func planRoute(to place: SavedPlace, avoidsTolls: Bool) async throws -> NavigationRoute {
        do {
            return try await RoutePlanner.route(to: place.coordinate, named: place.name, from: snapshot.position, avoidsTolls: avoidsTolls)
        } catch {
            try await Task.sleep(for: .seconds(1))
            return try await RoutePlanner.route(to: place.coordinate, named: place.name, from: snapshot.position, avoidsTolls: avoidsTolls)
        }
    }

    /// The stop the route goes through next, if any.
    var nextStop: Waypoint? { guidance?.remainingStops.first }

    /// The iPhone plans it while in reach, and sends the new route; on its own, the Watch plans it.
    func skipNextStop() {
        guard let guidance, nextStop != nil, !isRerouting else { return }
        if source == .phone, WCSession.default.isReachable {
            send(.skipStop)
            return
        }
        let routeID = guidance.route.id
        let position = snapshot.position
        isRerouting = true
        Task {
            defer { isRerouting = false }
            guard let newRoute = try? await guidance.routeSkippingNextStop(from: position),
                  self.guidance?.route.id == routeID else { return }
            setRoute(newRoute)
        }
    }

    private func sendToPhone(_ route: NavigationRoute) {
        guard WCSession.isSupported(), WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(NavigationEnvelope(route: route)) else { return }
        WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    func stopNavigation() {
        send(.stopNavigation)
        setRoute(nil)
    }

    /// Pauses the ride on both devices; the iPhone's next update confirms it.
    func setPaused(_ paused: Bool) {
        guard isRiding, paused != snapshot.isPaused else { return }
        send(paused ? .pause : .resume)
        if paused {
            localStats.pause(at: .now)
        } else {
            localStats.unpause(at: .now)
        }
        if source == .watch {
            snapshot = localStats.snapshot
        } else {
            snapshot.isPaused = paused
            snapshot.pausedAt = paused ? .now : nil
        }
        publishWidgets()
    }

    /// The iPhone opened the app through HealthKit when its ride started.
    func handleWorkoutLaunch() {
        beginRide(startDate: .now)
    }

    private func beginRide(startDate: Date) {
        if !isRiding {
            localStats.start(at: startDate)
            snapshot = localStats.snapshot
            phoneJoinedRide = false
            track = []
            speedAlert = nil
        }
        startWorkout()
        sourceTimer?.invalidate()
        sourceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.chooseSource() }
        }
        chooseSource()
        publishWidgets()
    }

    private func endRide() {
        if !phoneJoinedRide {
            sendTrip(WatchTrip(snapshot: localStats.snapshot, endDate: .now, track: track))
        }
        track = []
        speedAlert = nil
        isOverSpeedLimit = false
        localStats.stop()
        snapshot.isRiding = false
        snapshot.leanAngle = 0
        sourceTimer?.invalidate()
        sourceTimer = nil
        stopLocalGPS()
        workout?.end()
        workout = nil
        source = nil
        guidance = nil
        publishWidgets()
    }

    private func setRoute(_ route: NavigationRoute?) {
        guidance = route.map(Guidance.init)
        isRerouting = false
        updateGuidance()
        publishWidgets()
    }

    /// Guidance runs here, whatever the source of the position, so the wrist taps never depend on the link.
    private func updateGuidance() {
        guard var guidance, let position = snapshot.position else { return }
        let cues = guidance.update(position)
        self.guidance = guidance
        if WatchSettings.guidanceHaptics {
            cues.forEach(Haptics.play)
        }
        if guidance.state.isOffRoute, source == .watch {
            reroute(from: position)
        }
    }

    /// Only while the iPhone is gone: otherwise it reroutes and sends the new route.
    private func reroute(from position: Coordinate) {
        guard let route = guidance?.route, route.mode == .route, !route.followsTrack, !isRerouting,
              Date.now.timeIntervalSince(lastReroute) >= Self.rerouteInterval else { return }
        let remainingStops = guidance?.remainingStops ?? []
        isRerouting = true
        lastReroute = .now
        Task {
            defer { isRerouting = false }
            guard let newRoute = try? await RoutePlanner.route(
                to: route.destination,
                named: route.destinationName,
                via: remainingStops,
                from: position,
                avoidsTolls: route.avoidsTolls
            ), guidance?.route.destination == route.destination else { return }
            guidance = Guidance(route: newRoute)
            updateGuidance()
            publishWidgets()
        }
    }

    /// Queued: delivered whenever the iPhone comes back in reach, even hours later.
    private func sendTrip(_ trip: WatchTrip) {
        guard trip.snapshot.distance > 0, trip.track.count >= 2, WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(trip) else { return }
        Logger(subsystem: "com.guillaumeprost.Virage", category: "watch")
            .notice("Sending trip: \(trip.snapshot.distance, privacy: .public) m, \(trip.track.count, privacy: .public) points")
        let url = FileManager.default.temporaryDirectory.appending(path: "trip-\(UUID().uuidString).json")
        guard (try? data.write(to: url)) != nil else { return }
        WCSession.default.transferFile(url, metadata: WatchMessage.metadata(.trip))
    }

    /// Whatever the source of the speed: the warning is on the wrist.
    private func checkSpeed() {
        guard isRiding, !snapshot.isPaused, let limit = WatchSettings.speedLimit else {
            speedAlert = nil
            isOverSpeedLimit = false
            return
        }
        if speedAlert?.limit != limit {
            speedAlert = SpeedAlert(limit: limit)
        }
        if speedAlert?.update(speed: snapshot.speed, at: .now) == true {
            Haptics.playSpeedAlert()
        }
        isOverSpeedLimit = speedAlert?.isOver ?? false
    }

    private func publishWidgets() {
        var state = RideWidgetState(
            isRiding: isRiding,
            startDate: snapshot.timerStart,
            distance: Format.distance(snapshot.distance, unit),
            isPaused: snapshot.isPaused
        )
        if isRiding, let guidance = guidance?.state {
            let instruction = guidance.hasArrived || guidance.mode == .compass ? guidance.destinationName : guidance.instruction
            let symbol = guidance.hasArrived ? Maneuver.arrive.symbolName
                : guidance.mode == .compass ? "safari"
                : guidance.isOffRoute ? "arrow.triangle.2.circlepath"
                : guidance.maneuver.symbolName
            // Rounded to the minute, so the estimate drifting by seconds does not count as a change.
            let arrival = guidance.arrivalDate(from: .now).map { Date(timeIntervalSinceReferenceDate: ($0.timeIntervalSinceReferenceDate / 60).rounded() * 60) }
            state.navigation = RideWidgetState.Navigation(symbol: symbol, instruction: instruction, arrival: arrival)
        }
        widgets.publish(state)
    }

    private func chooseSource() {
        guard isRiding else { return }
        if Date.now.timeIntervalSince(lastPhoneUpdate) < Self.phoneTimeout {
            source = .phone
            stopLocalGPS()
        } else {
            if source == .phone {
                // Carry on from the iPhone's figures rather than from zero.
                localStats.resume(from: snapshot)
            }
            source = .watch
            startLocalGPS()
            snapshot = localStats.snapshot
        }
    }

    private func receiveRoute(_ envelope: NavigationEnvelope) {
        // The iPhone sends the route again whenever the Watch reconnects; restarting the same guidance would
        // repeat the cues already played.
        guard envelope.route?.id != guidance?.route.id else { return }
        setRoute(envelope.route)
    }

    /// A relaunched Watch app starts without the route; the iPhone keeps it and sends it on request.
    private func requestRoute() {
        send(.requestRoute)
    }

    private func receive(_ phoneSnapshot: RideSnapshot, unit: SpeedUnit) {
        self.unit = unit
        if phoneSnapshot.isRiding {
            lastPhoneUpdate = .now
            phoneJoinedRide = true
            snapshot = phoneSnapshot
            if workout == nil || sourceTimer == nil {
                beginRide(startDate: phoneSnapshot.startDate ?? .now)
            } else if source != .phone {
                chooseSource()
            }
        } else if isRiding {
            // An idle iPhone only ends a ride it took part in; otherwise it simply never got the start command.
            if phoneJoinedRide {
                endRide()
                snapshot = phoneSnapshot
            }
        } else {
            snapshot = phoneSnapshot
        }
        updateGuidance()
        checkSpeed()
        publishWidgets()
    }

    private func send(_ command: WatchMessage.Command) {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(WatchMessage.payload(command), replyHandler: nil)
    }

    private func startWorkout() {
        guard workout == nil else { return }
        guard let session = try? HKWorkoutSession(healthStore: healthStore, configuration: .motorcycleRide) else { return }
        session.delegate = self
        session.startActivity(with: .now)
        workout = session
    }

    private func startLocalGPS() {
        guard !isLocalGPSRunning else { return }
        isLocalGPSRunning = true
        locationManager.startUpdatingLocation()
    }

    private func stopLocalGPS() {
        guard isLocalGPSRunning else { return }
        isLocalGPSRunning = false
        locationManager.stopUpdatingLocation()
    }
}

extension WatchRideModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for location in locations where localStats.ingest(location) {
                if isRiding, source == .watch, !phoneJoinedRide, !localStats.snapshot.isPaused,
                   track.last.map({ location.timestamp.timeIntervalSince($0.timestamp) >= 1 }) ?? true {
                    track.append(TrackPoint(location))
                }
            }
            if source == .watch {
                snapshot = localStats.snapshot
                updateGuidance()
                checkSpeed()
                publishWidgets()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

extension WatchRideModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in requestRoute() }
        guard let (snapshot, unit) = WatchMessage.snapshot(in: session.receivedApplicationContext) else { return }
        Task { @MainActor in receive(snapshot, unit: unit) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in requestRoute() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let places = WatchMessage.places(in: message) {
            Task { @MainActor in
                self.places = places
                WatchSettings.save(places)
            }
        }
        guard let (snapshot, unit) = WatchMessage.snapshot(in: message) else { return }
        Task { @MainActor in receive(snapshot, unit: unit) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let envelope = try? JSONDecoder().decode(NavigationEnvelope.self, from: messageData) else { return }
        Task { @MainActor in receiveRoute(envelope) }
    }

    /// The file is deleted when this returns, so it is read right here.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard
            let data = try? Data(contentsOf: file.fileURL),
            let envelope = try? JSONDecoder().decode(NavigationEnvelope.self, from: data)
        else { return }
        Task { @MainActor in receiveRoute(envelope) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let places = WatchMessage.places(in: userInfo) else { return }
        Task { @MainActor in
            self.places = places
            WatchSettings.save(places)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let (snapshot, unit) = WatchMessage.snapshot(in: applicationContext) else { return }
        Task { @MainActor in receive(snapshot, unit: unit) }
    }
}

extension WatchRideModel: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in workout = nil }
    }
}
