import Foundation
import SwiftData

/// A saved place, offered at the top of the search tab. Home and work have one slot each, as in Maps.
@Model
final class FavoritePlace {
    enum Kind: String, CaseIterable, Codable {
        case home, work, other

        var title: String {
            switch self {
            case .home: "Maison"
            case .work: "Travail"
            case .other: "Favori"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house.fill"
            case .work: "briefcase.fill"
            case .other: "star.fill"
            }
        }
    }

    var kindRawValue: String
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(_ destination: Destination, kind: Kind, at date: Date) {
        kindRawValue = kind.rawValue
        name = destination.name
        subtitle = destination.subtitle
        latitude = destination.coordinate.latitude
        longitude = destination.coordinate.longitude
        createdAt = date
    }

    var kind: Kind {
        Kind(rawValue: kindRawValue) ?? .other
    }

    /// Home and work show their role; other favorites show their own name.
    var title: String {
        kind == .other ? name : kind.title
    }

    var destination: Destination {
        Destination(name: name, subtitle: subtitle, coordinate: Coordinate(latitude: latitude, longitude: longitude))
    }

    func isSamePlace(as destination: Destination) -> Bool {
        name == destination.name
            && abs(latitude - destination.coordinate.latitude) < 0.0001
            && abs(longitude - destination.coordinate.longitude) < 0.0001
    }

    /// Home and work replace the previous one; another favorite is added unless it is already there.
    static func save(_ destination: Destination, as kind: Kind, in context: ModelContext, at date: Date = .now) {
        let all = (try? context.fetch(FetchDescriptor<FavoritePlace>())) ?? []
        switch kind {
        case .home, .work:
            all.filter { $0.kind == kind }.forEach(context.delete)
        case .other:
            if all.contains(where: { $0.kind == .other && $0.isSamePlace(as: destination) }) {
                return
            }
        }
        context.insert(FavoritePlace(destination, kind: kind, at: date))
        try? context.save()
    }

    /// Favorites in the order Maps shows them: home, work, then the others oldest first.
    static func sorted(_ places: [FavoritePlace]) -> [FavoritePlace] {
        let order: [Kind] = [.home, .work, .other]
        return places.sorted {
            let lhs = order.firstIndex(of: $0.kind) ?? 2, rhs = order.firstIndex(of: $1.kind) ?? 2
            return lhs == rhs ? $0.createdAt < $1.createdAt : lhs < rhs
        }
    }
}
