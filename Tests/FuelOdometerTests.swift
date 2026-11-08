import Foundation
import Testing
@testable import Virage

/// The kilometers since the fill-up: written every few hundred meters, never lost at a pause or at the pump.
@Suite("Fuel odometer")
struct FuelOdometerTests {
    /// Fresh preferences for each test, so nothing leaks into the app's own.
    private func defaults() -> UserDefaults {
        let name = "FuelOdometerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func stored(_ defaults: UserDefaults) -> Double {
        FuelSettings.loadSinceRefuel(from: defaults)
    }

    @Test("Starts from the count kept on disk")
    func startsFromDisk() {
        let defaults = defaults()
        FuelSettings.save(sinceRefuel: 42_000, to: defaults)
        #expect(RefuelOdometer(defaults: defaults).meters == 42_000)
    }

    @Test("Short stretches stay in memory")
    func shortStretchesAreNotWritten() {
        let defaults = defaults()
        var odometer = RefuelOdometer(defaults: defaults)
        for _ in 0..<4 {
            odometer.add(100)
        }
        #expect(odometer.meters == 400)
        #expect(stored(defaults) == 0)
    }

    @Test("Written once 500 m have built up, then counted again from there")
    func writtenEveryInterval() {
        let defaults = defaults()
        var odometer = RefuelOdometer(defaults: defaults)
        for _ in 0..<5 {
            odometer.add(100)
        }
        #expect(stored(defaults) == 500)
        odometer.add(300)
        #expect(stored(defaults) == 500)
        odometer.add(250)
        #expect(stored(defaults) == 1_050)
    }

    @Test("A pause or the end of a ride writes what is left")
    func saveWritesTheRest() {
        let defaults = defaults()
        var odometer = RefuelOdometer(defaults: defaults)
        odometer.add(120)
        odometer.save()
        #expect(stored(defaults) == 120)
    }

    @Test("The pump resets the count on disk at once")
    func resetIsWrittenAtOnce() {
        let defaults = defaults()
        FuelSettings.save(sinceRefuel: 180_000, to: defaults)
        var odometer = RefuelOdometer(defaults: defaults)
        odometer.add(50)
        odometer.reset()
        #expect(odometer.meters == 0)
        #expect(stored(defaults) == 0)
    }

    @Test("A standing or backwards fix counts nothing")
    func ignoresNonPositiveDistances() {
        var odometer = RefuelOdometer(defaults: defaults())
        odometer.add(0)
        odometer.add(-30)
        #expect(odometer.meters == 0)
    }

    @Test("Nothing is lost across a relaunch after a save")
    func survivesARelaunch() {
        let defaults = defaults()
        var odometer = RefuelOdometer(defaults: defaults)
        odometer.add(1_234)
        odometer.add(66)
        odometer.save()
        #expect(RefuelOdometer(defaults: defaults).meters == 1_300)
    }
}
