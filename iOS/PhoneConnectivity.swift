import Foundation
import OSLog
import HealthKit
import WatchConnectivity

/// The iPhone side of the link with the Watch: pushes the live snapshot, receives start and stop commands.
@MainActor
@Observable
final class PhoneConnectivity: NSObject {
    private(set) var isWatchReachable = false
    private(set) var isWatchAppInstalled = false

    @ObservationIgnored var onCommand: ((WatchMessage.Command) -> Void)?
    /// A destination chosen on the Watch.
    @ObservationIgnored var onRoute: ((NavigationRoute?) -> Void)?
    /// A ride the Watch recorded without the iPhone.
    @ObservationIgnored var onTrip: ((WatchTrip) -> Void)?
    @ObservationIgnored private var sentPlaces: [SavedPlace]?
    /// Kept for when the session finishes activating: the first list usually comes before.
    @ObservationIgnored private var latestPlaces: [SavedPlace]?
    @ObservationIgnored private var lastSent = Date.distantPast
    /// Kept to send again to a Watch app that was relaunched mid-route.
    @ObservationIgnored private var currentRoute: NavigationRoute?
    /// The sensors update 25 times a second; the Watch needs two.
    @ObservationIgnored private let minimumInterval: TimeInterval = 0.5

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// `force` bypasses the throttle, for state changes the Watch must not miss.
    func send(_ snapshot: RideSnapshot, force: Bool = false) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSent) >= minimumInterval else { return }
        guard let payload = WatchMessage.payload(snapshot, unit: .current) else { return }
        if force, session.isWatchAppInstalled {
            // Delivered later if the Watch is not reachable right now.
            try? session.updateApplicationContext(payload)
        }
        guard session.isReachable else { return }
        lastSent = now
        session.sendMessage(payload, replyHandler: nil)
    }

    /// A message reaches the Watch at once but only while it is in reach and below the message size limit;
    /// a file is queued and delivered later, but can take seconds, so it is only the fallback.
    func send(route: NavigationRoute?) {
        currentRoute = route
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        // Only the latest route matters.
        session.outstandingFileTransfers.forEach { $0.cancel() }
        guard let data = try? JSONEncoder().encode(NavigationEnvelope(route: route)) else { return }
        if session.isReachable, data.count <= Self.maxMessageSize {
            // Called on a WatchConnectivity queue: marked `@Sendable` so it does not inherit the main actor,
            // which would trap at runtime.
            session.sendMessageData(data, replyHandler: nil) { @Sendable _ in
                Task { @MainActor in self.transfer(data) }
            }
        } else {
            transfer(data)
        }
    }

    /// WatchConnectivity rejects messages above about 64 KB.
    private static let maxMessageSize = 60_000

    private func transfer(_ data: Data) {
        let url = FileManager.default.temporaryDirectory.appending(path: "route-\(UUID().uuidString).json")
        guard (try? data.write(to: url)) != nil else { return }
        WCSession.default.transferFile(url, metadata: WatchMessage.metadata(.route))
    }

    /// The queued transfer can take minutes; a Watch asking right now gets the places right away.
    private func sendPlacesNow() {
        guard let latestPlaces, WCSession.default.isReachable,
              let payload = WatchMessage.payload(latestPlaces) else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil)
    }

    /// Favorites and recents, so the Watch can offer them even without the iPhone in reach.
    func send(places: [SavedPlace]) {
        latestPlaces = places
        guard places != sentPlaces, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled,
              let payload = WatchMessage.payload(places) else { return }
        // Only the latest list matters.
        session.outstandingUserInfoTransfers.forEach { $0.cancel() }
        session.transferUserInfo(payload)
        sentPlaces = places
    }

    private func refreshState() {
        let session = WCSession.default
        isWatchReachable = session.isReachable
        isWatchAppInstalled = session.isWatchAppInstalled
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in
            refreshState()
            // Sent again after each launch: the Watch may have been reset or paired since.
            sentPlaces = nil
            if let latestPlaces {
                send(places: latestPlaces)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another Watch.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in refreshState() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in refreshState() }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    /// The file is deleted when this returns, so it is read right here.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let log = Logger(subsystem: "com.guillaumeprost.Virage", category: "watch")
        guard WatchMessage.fileKind(in: file.metadata) == .trip else {
            log.error("File from the Watch without a trip kind: \(String(describing: file.metadata), privacy: .public)")
            return
        }
        let trip: WatchTrip
        do {
            trip = try JSONDecoder().decode(WatchTrip.self, from: Data(contentsOf: file.fileURL))
        } catch {
            log.error("Unreadable trip from the Watch: \(error, privacy: .public)")
            return
        }
        log.notice("Trip from the Watch: \(trip.snapshot.distance, privacy: .public) m, \(trip.track.count, privacy: .public) points")
        Task { @MainActor in onTrip?(trip) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let envelope = try? JSONDecoder().decode(NavigationEnvelope.self, from: messageData) else { return }
        Task { @MainActor in onRoute?(envelope.route) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchMessage.command(in: message) else { return }
        Task { @MainActor in
            if command == .requestRoute {
                send(route: currentRoute)
                sendPlacesNow()
            } else {
                onCommand?(command)
            }
        }
    }
}

/// Opens the Watch app when a ride starts on the iPhone. Only a workout can wake the Watch app this way.
@MainActor
final class WatchWorkoutLauncher {
    private let healthStore = HKHealthStore()

    func launch() {
        guard HKHealthStore.isHealthDataAvailable(), WCSession.isSupported(), WCSession.default.isWatchAppInstalled else {
            return
        }
        healthStore.startWatchApp(with: .motorcycleRide) { _, _ in }
    }
}
