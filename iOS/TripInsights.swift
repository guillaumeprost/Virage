import CoreLocation
import Foundation
import SwiftUI

/// What colors a recorded track.
enum TrackColoring: String, CaseIterable, Identifiable {
    case speed
    case lean

    var id: Self { self }

    var label: String {
        switch self {
        case .speed: "Vitesse"
        case .lean: "Inclinaison"
        }
    }

    /// Bounds between the color bands: m/s for speed (30, 60, 90, 120 km/h), degrees for lean.
    var thresholds: [Double] {
        switch self {
        case .speed: [30, 60, 90, 120].map { $0 / 3.6 }
        case .lean: [15, 25, 35, 45]
        }
    }

    /// One more band than thresholds: calm to hot.
    static let colors: [Color] = [.blue, .cyan, .green, .yellow, .red]

    /// The band's color, neutral where a point has no value.
    static func color(for band: Int?) -> Color {
        band.map { colors[$0] } ?? .gray
    }

    /// The value a point holds for this coloring, nil when it has none.
    func value(of point: TrackPoint) -> Double? {
        switch self {
        case .speed: point.speed
        case .lean: point.lean.map(abs)
        }
    }

    func band(of value: Double) -> Int {
        thresholds.firstIndex { value < $0 } ?? thresholds.count
    }

    /// Under each band of the legend: "< 30", "30", … in the rider's unit.
    func legend(_ unit: SpeedUnit) -> [String] {
        let bounds = thresholds.map { threshold in
            switch self {
            case .speed: Format.speed(threshold, unit)
            case .lean: Format.lean(threshold)
            }
        }
        return ["< " + bounds[0]] + bounds.map { $0 + "+" }
    }
}

/// A stretch of track in one color band.
struct TrackSegment: Identifiable {
    let id: Int
    /// nil where the point has no value, drawn neutral.
    let band: Int?
    let coordinates: [CLLocationCoordinate2D]
}

/// One of the most leaned bends of a trip, to pin on its map.
struct LeanPeak: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    /// Degrees, negative to the left.
    let lean: Double
}

enum TripInsights {
    /// Below this, a bend is not worth pinning.
    static let peakMinimumLean = 15.0
    /// Two pinned bends at least this far apart: the peaks of one bend, or of one run of hairpins, are one pin.
    static let peakSpacing = 1_500.0

    /// Points on either side taken into account before banding: on the median of the window, a jolt of a second
    /// does not change the color.
    static let smoothing = 2

    /// Consecutive points of the same band, drawn as one line. Each stretch ends on the first point of the next,
    /// so the line has no gaps.
    static func segments(_ track: [TrackPoint], by coloring: TrackColoring) -> [TrackSegment] {
        let values = track.map(coloring.value(of:))
        var segments: [TrackSegment] = []
        var coordinates: [CLLocationCoordinate2D] = []
        var band: Int?
        for (index, point) in track.enumerated() {
            let pointBand = smoothed(values, at: index).map(coloring.band(of:))
            if coordinates.isEmpty {
                band = pointBand
            } else if pointBand != band {
                coordinates.append(point.coordinate)
                segments.append(TrackSegment(id: segments.count, band: band, coordinates: coordinates))
                coordinates = []
                band = pointBand
            }
            coordinates.append(point.coordinate)
        }
        if coordinates.count >= 2 {
            segments.append(TrackSegment(id: segments.count, band: band, coordinates: coordinates))
        }
        return segments
    }

    private static func smoothed(_ values: [Double?], at index: Int) -> Double? {
        guard values[index] != nil else { return nil }
        return median(values[window(around: index, in: values.count)].compactMap { $0 })
    }

    /// The fixes either side of one, for smoothing.
    private static func window(around index: Int, in count: Int) -> ClosedRange<Int> {
        max(index - smoothing, 0)...min(index + smoothing, count - 1)
    }

    /// A median rather than a mean: a one-second jolt does not move it.
    private static func median(_ values: some Collection<Double>) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// The most leaned bends, at most `count`, apart from one another.
    static func leanPeaks(_ track: [TrackPoint], count: Int = 3) -> [LeanPeak] {
        let candidates = track.enumerated()
            .compactMap { index, point in point.lean.map { (index, point, $0) } }
            .filter { abs($0.2) >= peakMinimumLean }
            .sorted { abs($0.2) > abs($1.2) }
        var peaks: [LeanPeak] = []
        var positions: [Coordinate] = []
        for (index, point, lean) in candidates {
            guard positions.allSatisfy({ Geo.distance($0, point.position) >= peakSpacing }) else { continue }
            positions.append(point.position)
            peaks.append(LeanPeak(id: index, coordinate: point.coordinate, lean: lean))
            if peaks.count == count { break }
        }
        return peaks
    }
}

extension TripInsights {
    /// GPS altitude wanders by a few meters: a climb counts only once it passes this, so the noise does not add up.
    static let climbThreshold = 5.0

    /// Meters climbed, and the highest point, from altitudes smoothed over a few fixes.
    static func elevation(_ track: [TrackPoint]) -> (gain: Double, highest: Double?) {
        let altitudes = track.map(\.altitude)
        guard !altitudes.isEmpty else { return (0, nil) }
        let smoothed = altitudes.indices.map { median(altitudes[window(around: $0, in: altitudes.count)]) }
        var gain = 0.0
        var anchor = smoothed[0]
        for altitude in smoothed.dropFirst() {
            if altitude - anchor >= climbThreshold {
                gain += altitude - anchor
                anchor = altitude
            } else if altitude < anchor {
                // Going down moves the reference: the next climb counts from the bottom.
                anchor = altitude
            }
        }
        return (gain, smoothed.max())
    }
}

/// The figures of a trip that summaries and records need.
struct TripFigures: Hashable {
    var start: Date
    var distance: Double
    var movingTime: TimeInterval
    var maxSpeed: Double
    var maxLean: Double
    var elevationGain: Double = 0
    var maxAltitude: Double = 0
}

/// The trips of one month, added up.
struct MonthSummary: Identifiable, Equatable {
    /// The first instant of the month.
    let month: Date
    let count: Int
    let distance: Double
    let movingTime: TimeInterval

    var id: Date { month }
}

extension TripInsights {
    /// Newest month first.
    /// The key trips are grouped under: the summaries and the list's sections must agree on it.
    static func monthStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    static func months(_ trips: [TripFigures], calendar: Calendar = .current) -> [MonthSummary] {
        let grouped = Dictionary(grouping: trips) { monthStart(of: $0.start, calendar: calendar) }
        return grouped
            .map { month, trips in
                MonthSummary(
                    month: month,
                    count: trips.count,
                    distance: trips.reduce(0) { $0 + $1.distance },
                    movingTime: trips.reduce(0) { $0 + $1.movingTime }
                )
            }
            .sorted { $0.month > $1.month }
    }

    /// The index of the trip holding the highest value, if any trip has one.
    static func record(_ trips: [TripFigures], by value: (TripFigures) -> Double) -> Int? {
        trips.indices
            .filter { value(trips[$0]) > 0 }
            .max { value(trips[$0]) < value(trips[$1]) }
    }
}
