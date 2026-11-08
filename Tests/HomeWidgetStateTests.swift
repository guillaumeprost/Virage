import Foundation
import Testing
@testable import Virage

@Suite("Home widget figures")
struct HomeWidgetStateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func state(monthStart: Date) -> HomeWidgetState {
        HomeWidgetState(
            sinceRefuel: 142_300,
            fuelRemaining: nil,
            fuelRange: nil,
            isFuelLow: false,
            lastTrip: nil,
            month: .init(start: monthStart, count: 6, distance: 412_000, movingTime: 25_200),
            unit: .kilometersPerHour
        )
    }

    @Test("The month total stands until the month turns")
    func sameMonth() {
        let home = state(monthStart: date(2026, 11, 1))
        #expect(home.asOf(date(2026, 11, 30), calendar: calendar) == home)
    }

    @Test("A new month starts from zero")
    func newMonth() {
        let home = state(monthStart: date(2026, 11, 1))
        let december = home.asOf(date(2026, 12, 2), calendar: calendar)
        #expect(december.month.count == 0)
        #expect(december.month.distance == 0)
        #expect(december.sinceRefuel == home.sinceRefuel)
    }

    @Test("The timeline turns over on the first of next month")
    func timeline() {
        let home = state(monthStart: date(2026, 11, 1))
        let entries = home.timeline(from: date(2026, 11, 8), calendar: calendar)
        #expect(entries.count == 2)
        #expect(entries[0].state.month.count == 6)
        #expect(entries[1].date == calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        #expect(entries[1].state.month.count == 0)
    }

    @Test("The tank reads the range when tracked, the counter otherwise")
    func tank() {
        var home = state(monthStart: date(2026, 11, 1))
        #expect(home.tank.caption == "depuis le plein")
        home.fuelRemaining = 87_600
        home.fuelRange = 250_000
        #expect(home.tank.value == "88 km")
        #expect(home.tank.caption == "d'autonomie")
        #expect(home.monthCaption == "6 trajets · 412 km")
    }

    @Test("The figures travel to the Watch intact")
    func message() throws {
        let home = state(monthStart: date(2026, 11, 1))
        let payload = try #require(WatchMessage.payload(home))
        #expect(WatchMessage.isHome(payload))
        #expect(WatchMessage.home(in: payload) == home)
        #expect(WatchMessage.places(in: payload) == nil)
    }

    @Test("The gauge needs a tracked range, and never shows more than a full tank")
    func gauge() {
        var home = state(monthStart: date(2026, 11, 1))
        #expect(home.gauge == nil)
        home.fuelRemaining = 300_000
        home.fuelRange = 250_000
        #expect(home.gauge?.remaining == 250_000)
        #expect(home.gauge?.range == 250_000)
        home.fuelRange = 0
        #expect(home.gauge == nil)
    }

    @Test("Round slots read whole kilometers or miles")
    func wholeDistance() {
        var home = state(monthStart: date(2026, 11, 1))
        #expect(home.wholeDistance(142_300) == "142")
        home.unit = .milesPerHour
        #expect(home.wholeDistance(160_934) == "100")
    }

    @Test("One line for the inline slots")
    func inlineCaption() {
        let home = state(monthStart: date(2026, 11, 1))
        #expect(home.inlineCaption == "142.3 km · mois 412 km")
    }

    @Test("The pump turns to a warning in the reserve")
    func fuelSymbol() {
        var home = state(monthStart: date(2026, 11, 1))
        #expect(home.fuelSymbol == "fuelpump.fill")
        home.isFuelLow = true
        #expect(home.fuelSymbol == "fuelpump.exclamationmark.fill")
    }

    @Test("One ride, one trajet")
    func singularMonth() {
        var home = state(monthStart: date(2026, 11, 1))
        home.month.count = 1
        home.month.distance = 87_400
        #expect(home.monthCaption == "1 trajet · 87 km")
    }
}
