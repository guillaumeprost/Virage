import MediaPlayer
import SwiftUI

/// What Apple Music is playing, and its three controls: only the Music app lets another app read its track
/// and drive it.
///
/// Shown only while music plays, and for a minute after a pause, so the rider can start it again.
@MainActor
@Observable
final class NowPlaying {
    struct Track: Equatable {
        var title: String
        var artist: String?
    }

    /// Nil until the rider lets Virage read the library: the controls still work, without the title.
    private(set) var track: Track?
    private(set) var artwork: UIImage?
    private(set) var isPlaying = false
    private(set) var isVisible = false

    /// How long the player stays after a pause.
    @ObservationIgnored var lingering: TimeInterval = 60

    @ObservationIgnored private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var isDemo = false

    func start() {
        #if DEBUG
        // -demoMusic YES: a track playing, for the simulator, which has no Music app.
        if UserDefaults.standard.bool(forKey: "demoMusic") {
            isDemo = true
            track = Track(title: "Highway Star", artist: "Deep Purple")
            isPlaying = true
            isVisible = true
            return
        }
        #endif
        guard observers.isEmpty else { return }
        player.beginGeneratingPlaybackNotifications()
        for name in [Notification.Name.MPMusicPlayerControllerPlaybackStateDidChange, .MPMusicPlayerControllerNowPlayingItemDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    /// Asked when the app comes back: the Music app may have started or stopped meanwhile.
    func refresh() {
        guard !isDemo else { return }
        let isPlaying = player.playbackState == .playing
        // The library is asked for the first time music actually plays, when the question makes sense.
        if isPlaying, MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
        let item = MPMediaLibrary.authorizationStatus() == .authorized ? player.nowPlayingItem : nil
        let track = item.map { Track(title: $0.title ?? "Apple Music", artist: $0.artist) }
        if track != self.track {
            self.track = track
            artwork = item?.artwork?.image(at: CGSize(width: 96, height: 96))
        }
        setPlaying(isPlaying)
    }

    func togglePlayPause() {
        if !isDemo {
            isPlaying ? player.pause() : player.play()
        }
        setPlaying(!isPlaying)
    }

    func next() {
        guard !isDemo else { return }
        player.skipToNextItem()
    }

    /// Back to the start of the track, as on a car radio; twice in a row, to the one before.
    func previous() {
        guard !isDemo else { return }
        if player.currentPlaybackTime > 3 {
            player.skipToBeginning()
        } else {
            player.skipToPreviousItem()
        }
    }

    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        hideTask?.cancel()
        if playing {
            isVisible = true
        } else if isVisible {
            let delay = lingering
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.isVisible = false
            }
        }
    }
}

/// The music, in a capsule like the fuel and the passes: the cover, the title, and three buttons sized for gloves.
/// Compact, it keeps the cover and the two buttons that matter on the road.
struct MusicCapsule: View {
    let music: NowPlaying
    var isCompact = false
    /// Off where the title needs the room, as in the narrow landscape panel.
    var showsPrevious = true
    @Environment(\.dashboardStyle) private var style

    var body: some View {
        HStack(spacing: 2) {
            cover
                .padding(.leading, 5)
                .padding(.trailing, 6)
            if !isCompact {
                VStack(alignment: .leading, spacing: 0) {
                    Text(music.track?.title ?? "Apple Music")
                        .font(style.labelFont(.subheadline.weight(.semibold), size: 14, relativeTo: .subheadline))
                    if let artist = music.track?.artist {
                        Text(artist)
                            .font(style.labelFont(.caption, size: 12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsPrevious {
                    control("backward.fill", label: "Morceau précédent", action: music.previous)
                }
            }
            control(music.isPlaying ? "pause.fill" : "play.fill", label: music.isPlaying ? "Pause" : "Lecture", action: music.togglePlayPause)
            control("forward.fill", label: "Morceau suivant", action: music.next)
        }
        .padding(.trailing, 4)
        .frame(height: 52)
        .background { DashboardCapsule(isAlert: false) }
        .sensoryFeedback(.selection, trigger: music.isPlaying)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var cover: some View {
        ZStack {
            if let artwork = music.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                // Without access to the library: a plain square, as Music shows for a track with no cover.
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                Image(systemName: "music.note")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.rect(cornerRadius: style == .sport ? 4 : 8))
    }

    private func control(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
