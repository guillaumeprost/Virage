import Foundation
import SwiftData
import Testing
@testable import Virage

@MainActor
struct RecentDestinationTests {
    /// Kept alive for the whole test: a context outlives its container only to crash.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: RecentDestination.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func destination(_ name: String, latitude: Double = 45.84) -> Destination {
        Destination(name: name, subtitle: "Haute-Savoie", coordinate: Coordinate(latitude: latitude, longitude: 6.21))
    }

    private func names() throws -> [String] {
        try context.fetch(FetchDescriptor<RecentDestination>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)])).map(\.name)
    }

    @Test func keepsTheMostRecentFirst() throws {
        RecentDestination.record(destination("Talloires"), in: context, at: Date(timeIntervalSince1970: 1))
        RecentDestination.record(destination("Annecy", latitude: 45.9), in: context, at: Date(timeIntervalSince1970: 2))

        #expect(try names() == ["Annecy", "Talloires"])
    }

    @Test func keepsTheStopsOfATrip() throws {
        var trip = destination("Talloires")
        trip.via = [Waypoint(name: "Menthon", coordinate: Coordinate(latitude: 45.86, longitude: 6.19))]
        RecentDestination.record(destination("Talloires"), in: context, at: Date(timeIntervalSince1970: 1))
        RecentDestination.record(trip, in: context, at: Date(timeIntervalSince1970: 2))

        let recents = try context.fetch(FetchDescriptor<RecentDestination>(sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]))
        // The same place through a stop is another trip.
        #expect(recents.count == 2)
        #expect(recents.first?.destination.via.map(\.name) == ["Menthon"])
        #expect(recents.first?.summary == "Via Menthon")
        #expect(recents.last?.summary == "Haute-Savoie")
    }

    @Test func movesARepeatedDestinationUpInsteadOfDuplicatingIt() throws {
        RecentDestination.record(destination("Talloires"), in: context, at: Date(timeIntervalSince1970: 1))
        RecentDestination.record(destination("Annecy", latitude: 45.9), in: context, at: Date(timeIntervalSince1970: 2))
        RecentDestination.record(destination("Talloires"), in: context, at: Date(timeIntervalSince1970: 3))

        #expect(try names() == ["Talloires", "Annecy"])
    }

    @Test func forgetsTheOldestBeyondTheLimit() throws {
        for index in 0...RecentDestination.limit {
            RecentDestination.record(
                destination("Lieu \(index)", latitude: 45 + Double(index) / 100),
                in: context,
                at: Date(timeIntervalSince1970: Double(index))
            )
        }

        let kept = try names()
        #expect(kept.count == RecentDestination.limit)
        #expect(!kept.contains("Lieu 0"))
    }
}
