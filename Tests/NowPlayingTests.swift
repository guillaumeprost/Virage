import Foundation
import Testing
@testable import Virage

/// The music capsule shows while music plays, and lingers after a pause so the rider can start it again.
/// Runs on the demo track: the simulator has no Music app.
@MainActor
@Suite("Music player", .serialized)
struct NowPlayingTests {
    private func playing() -> NowPlaying {
        UserDefaults.standard.set(true, forKey: "demoMusic")
        defer { UserDefaults.standard.removeObject(forKey: "demoMusic") }
        let music = NowPlaying()
        music.lingering = 0.1
        music.start()
        return music
    }

    @Test("Shown while playing, with its track")
    func shownWhilePlaying() {
        let music = playing()
        #expect(music.isVisible)
        #expect(music.isPlaying)
        #expect(music.track?.title == "Highway Star")
    }

    @Test("A pause keeps it on screen for a while, then hides it")
    func lingersAfterAPause() async throws {
        let music = playing()
        music.togglePlayPause()
        #expect(!music.isPlaying)
        #expect(music.isVisible)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!music.isVisible)
    }

    @Test("Playing again before it hides keeps it")
    func resumeCancelsTheHiding() async throws {
        let music = playing()
        music.togglePlayPause()
        music.togglePlayPause()
        #expect(music.isPlaying)
        try await Task.sleep(for: .milliseconds(400))
        #expect(music.isVisible)
    }
}
