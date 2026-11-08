import SwiftUI
import WidgetKit

struct HomeEntry: TimelineEntry {
    let date: Date
    let state: HomeWidgetState
}

/// Redrawn when the app writes a new state: after a ride, at the pump, when the app goes to the background.
struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: .now, state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(HomeEntry(date: .now, state: (HomeWidgetState.load() ?? .placeholder).asOf(.now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let state = HomeWidgetState.load() ?? .placeholder
        let entries = state.timeline(from: .now).map { HomeEntry(date: $0.date, state: $0.state) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

/// Kilometers since the fill-up, the last ride and the month, at a glance.
struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetState.kind, provider: HomeProvider()) { entry in
            HomeWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Virage")
        .description("Les kilomètres depuis le plein, ta dernière sortie et le total du mois.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct HomeWidgetView: View {
    let state: HomeWidgetState
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: Pieces

    private var tankBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: state.fuelSymbol)
                .font(.title3)
                .foregroundStyle(state.isFuelLow ? .red : .blue)
            Spacer(minLength: 0)
            Text(state.tank.value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(state.isFuelLow ? .red : .primary)
            Text(state.tank.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Families

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            tankBlock
            Text("Ce mois-ci : \(Format.range(state.month.distance, state.unit))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            tankBlock
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if let trip = state.lastTrip {
                    Text("Dernière sortie")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Format.distance(trip.distance, state.unit))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text(trip.date.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Pas encore de sortie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Label(state.monthCaption, systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let gauge = state.gauge {
            Gauge(value: gauge.remaining, in: 0...gauge.range) {
                Image(systemName: state.fuelSymbol)
            } currentValueLabel: {
                Text(state.wholeDistance(gauge.remaining))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            VStack(spacing: 0) {
                Image(systemName: state.fuelSymbol)
                    .font(.caption)
                Text(state.wholeDistance(state.sinceRefuel))
                    .font(.headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(state.unit.distanceLabel)
                    .font(.caption2)
            }
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("\(state.tank.value) \(state.tank.caption)", systemImage: state.fuelSymbol)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let trip = state.lastTrip {
                Text("Dernière : \(Format.distance(trip.distance, state.unit))")
                    .lineLimit(1)
            }
            Text("Mois : \(state.monthCaption)")
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label(state.inlineCaption, systemImage: state.fuelSymbol)
    }
}

#Preview(as: .systemMedium) {
    HomeWidget()
} timeline: {
    HomeEntry(date: .now, state: .placeholder)
}
