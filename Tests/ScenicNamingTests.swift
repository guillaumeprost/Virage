import Foundation
import Testing
@testable import Virage

/// How the places found in Apple Maps are named, merged and ordered.
@Suite("Scenic places")
struct ScenicNamingTests {
    @Test("Passes read \"Col de …\", whatever the case or the article")
    func passNames() {
        #expect(ScenicSearch.displayName("col de Bluffy", kind: .pass) == "Col de Bluffy")
        #expect(ScenicSearch.displayName("Le Col de la Forclaz", kind: .pass) == "Col de la Forclaz")
        #expect(ScenicSearch.displayName("la col de la Croix", kind: .pass) == "Col de la Croix")
        #expect(ScenicSearch.displayName("Col des Aravis", kind: .pass) == "Col des Aravis")
    }

    @Test("A viewpoint keeps its article: it is part of its name")
    func viewpointNames() {
        #expect(ScenicSearch.displayName("La Tournette belvédère", kind: .viewpoint) == "La Tournette belvédère")
        #expect(ScenicSearch.displayName("point de vue du Semnoz", kind: .viewpoint) == "Point de vue du Semnoz")
    }

    @Test("The same place found twice is one pin")
    func mergesDuplicates() {
        let bluffy = Coordinate(latitude: 45.873, longitude: 6.212)
        let nearby = Coordinate(latitude: 45.8731, longitude: 6.2121)
        let merged = ScenicSearch.deduplicated([
            ("Col de Bluffy", .pass, bluffy),
            ("Col de Bluffy", .pass, nearby),
        ])
        #expect(merged.count == 1)
        #expect(merged.first?.2 == bluffy)
    }

    @Test("Two passes sharing a name far apart are both kept")
    func keepsNamesakesApart() {
        let merged = ScenicSearch.deduplicated([
            ("Col de la Forclaz", .pass, Coordinate(latitude: 45.808, longitude: 6.245)),
            ("Col de la Forclaz", .pass, Coordinate(latitude: 46.06, longitude: 7.0)),
        ])
        #expect(merged.count == 2)
    }

    @Test("Passes come in the order they were crossed")
    func crossingOrder() {
        let forclaz = TripPass(name: "Col de la Forclaz", latitude: 45.808, longitude: 6.245)
        let bluffy = TripPass(name: "Col de Bluffy", latitude: 45.873, longitude: 6.212)
        let passes = ScenicSearch.crossings([(forclaz, 12_000), (bluffy, 3_000)])
        #expect(passes.map(\.name) == ["Col de Bluffy", "Col de la Forclaz"])
    }

    @Test("A pass and a place named after it at the same spot are one crossing")
    func mergesCrossingsAtTheSameSpot() {
        let pass = TripPass(name: "Col de Bluffy", latitude: 45.873, longitude: 6.212)
        let restaurant = TripPass(name: "Col de Bluffy Auberge", latitude: 45.8735, longitude: 6.2125)
        let passes = ScenicSearch.crossings([(pass, 3_000), (restaurant, 3_050)])
        #expect(passes.map(\.name) == ["Col de Bluffy"])
    }
}
