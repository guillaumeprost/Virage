import Foundation
import SwiftData
import Testing
@testable import Virage

@MainActor
struct FavoritePlaceTests {
    /// Kept alive for the whole test: a context outlives its container only to crash.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: FavoritePlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func place(_ name: String, latitude: Double = 45.84) -> Destination {
        Destination(name: name, coordinate: Coordinate(latitude: latitude, longitude: 6.21))
    }

    private func favorites() throws -> [FavoritePlace] {
        FavoritePlace.sorted(try context.fetch(FetchDescriptor<FavoritePlace>()))
    }

    @Test func homeHasASingleSlot() throws {
        FavoritePlace.save(place("Rue A"), as: .home, in: context)
        FavoritePlace.save(place("Rue B", latitude: 45.9), as: .home, in: context)

        let homes = try favorites().filter { $0.kind == .home }
        #expect(homes.map(\.name) == ["Rue B"])
        #expect(homes.first?.title == "Maison")
    }

    @Test func addsOtherFavoritesWithoutDuplicates() throws {
        FavoritePlace.save(place("Col de la Forclaz"), as: .other, in: context)
        FavoritePlace.save(place("Col de la Forclaz"), as: .other, in: context)
        FavoritePlace.save(place("Talloires", latitude: 45.85), as: .other, in: context)

        #expect(try favorites().map(\.title) == ["Col de la Forclaz", "Talloires"])
    }

    @Test func listsHomeAndWorkFirst() throws {
        FavoritePlace.save(place("Talloires"), as: .other, in: context, at: Date(timeIntervalSince1970: 1))
        FavoritePlace.save(place("Bureau", latitude: 45.9), as: .work, in: context, at: Date(timeIntervalSince1970: 2))
        FavoritePlace.save(place("Chez moi", latitude: 45.8), as: .home, in: context, at: Date(timeIntervalSince1970: 3))

        #expect(try favorites().map(\.kind) == [.home, .work, .other])
    }
}
