import SwiftUI
import WidgetKit

@main
struct VirageWatchWidgets: WidgetBundle {
    var body: some Widget {
        RideComplication()
    }
}

/// On the watch face and in the Smart Stack: the kilometers since the fill-up, then the ride once it has started.
struct RideComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RideWidgetState.complicationKind, provider: RideProvider()) { entry in
            RideComplicationView(state: entry.state, home: entry.home)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Virage")
        .description("Les kilomètres depuis le plein, puis le trajet en cours et le prochain virage.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct RideEntry: TimelineEntry {
    let date: Date
    let state: RideWidgetState
    /// Sent by the iPhone: shown when no ride is under way.
    var home: HomeWidgetState?
    /// Raised during a ride, so the Smart Stack brings the widget to the top.
    let relevance: TimelineEntryRelevance?
}

struct RideProvider: TimelineProvider {
    func placeholder(in context: Context) -> RideEntry {
        // What the complication shows most of the time: the figures between two rides.
        RideEntry(date: .now, state: RideWidgetState(), home: .placeholder, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RideEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries()[0])
    }

    /// The Watch app reloads the timeline when the ride or the iPhone's figures change; only the turn of the
    /// month is scheduled here.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RideEntry>) -> Void) {
        completion(Timeline(entries: entries(), policy: .never))
    }

    private func entries() -> [RideEntry] {
        let state = RideWidgetState.load()
        let relevance = TimelineEntryRelevance(score: state.isRiding ? 100 : 0)
        guard let home = HomeWidgetState.load() else {
            return [RideEntry(date: .now, state: state, relevance: relevance)]
        }
        return home.timeline(from: .now).map { RideEntry(date: $0.date, state: state, home: $0.state, relevance: relevance) }
    }
}

/// The ride, or between two rides the iPhone's figures: decided once, here.
struct RideComplicationView: View {
    let state: RideWidgetState
    var home: HomeWidgetState?

    var body: some View {
        if !state.isRiding, let home {
            IdleComplication(home: home)
        } else {
            RideStateView(state: state)
        }
    }
}

private struct RideStateView: View {
    @Environment(\.widgetFamily) private var family
    let state: RideWidgetState

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryInline:
            inline
        default:
            rectangular
        }
    }

    private var symbol: String {
        state.navigation?.symbol ?? "gauge.with.dots.needle.67percent"
    }

    @ViewBuilder
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if state.isRiding, state.navigation == nil, let start = state.startDate {
                VStack(spacing: 0) {
                    Image(systemName: "motorcycle")
                        .font(.caption2)
                    Text(start, style: .timer)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
            } else {
                Image(systemName: symbol)
                    .font(.title2.weight(.bold))
                    .widgetAccentable()
            }
        }
    }

    private var corner: some View {
        Image(systemName: symbol)
            .font(.title2.weight(.bold))
            .widgetAccentable()
            .widgetLabel {
                if let start = state.startDate, state.isRiding, !state.isPaused {
                    Text(start, style: .timer)
                } else {
                    Text("Virage")
                }
            }
    }

    @ViewBuilder
    private var inline: some View {
        if let navigation = state.navigation, state.isRiding {
            Label(navigation.instruction, systemImage: navigation.symbol)
        } else if state.isRiding, let start = state.startDate {
            Label {
                Text(start, style: .timer)
            } icon: {
                Image(systemName: "motorcycle")
            }
        } else {
            Label("Virage", systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if state.isRiding, let navigation = state.navigation {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: navigation.symbol)
                        .font(.title3.weight(.bold))
                        .widgetAccentable()
                    Text(navigation.instruction)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                if let arrival = navigation.arrival {
                    Label {
                        Text(arrival, style: .time)
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if state.isRiding {
            VStack(alignment: .leading, spacing: 0) {
                Label(state.isPaused ? "En pause" : "Trajet", systemImage: state.isPaused ? "pause.fill" : "motorcycle")
                    .font(.headline)
                    .widgetAccentable()
                if let start = state.startDate, !state.isPaused {
                    Text(start, style: .timer)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                Text(state.distance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Virage", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                    .widgetAccentable()
                Text("Démarrer un trajet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


/// Between two rides: the tank, and the month, sent by the iPhone.
private struct IdleComplication: View {
    @Environment(\.widgetFamily) private var family
    let home: HomeWidgetState

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: Label(home.inlineCaption, systemImage: home.fuelSymbol)
        default: rectangular
        }
    }

    /// Read like the bike's own fuel gauge: the marker slides from green towards red.
    private static let fuelGradient = Gradient(colors: [.red, .yellow, .green])

    @ViewBuilder
    private var circular: some View {
        if let gauge = home.gauge {
            Gauge(value: gauge.remaining, in: 0...gauge.range) {
                Image(systemName: home.fuelSymbol)
            } currentValueLabel: {
                Text(home.wholeDistance(gauge.remaining))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Self.fuelGradient)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: home.fuelSymbol)
                        .font(.caption2)
                        .widgetAccentable()
                    Text(home.wholeDistance(home.sinceRefuel))
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(home.unit.distanceLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(3)
            }
        }
    }

    /// The range along the bezel when tracked, the counter otherwise.
    private var corner: some View {
        Image(systemName: home.fuelSymbol)
            .font(.title3.weight(.bold))
            .widgetAccentable()
            .widgetLabel {
                if let gauge = home.gauge {
                    Gauge(value: gauge.remaining, in: 0...gauge.range) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        // Same type as the maximum, which carries the range at the end of the arc.
                        Text("")
                    } maximumValueLabel: {
                        Text(Format.range(gauge.remaining, home.unit))
                    }
                    .tint(Self.fuelGradient)
                } else {
                    Text(Format.range(home.sinceRefuel, home.unit))
                }
            }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Virage", systemImage: "gauge.with.dots.needle.67percent")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Label {
                Text(home.tank.value)
                    .monospacedDigit()
            } icon: {
                Image(systemName: home.fuelSymbol)
                    .foregroundStyle(home.isFuelLow ? .red : .primary)
            }
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(home.tank.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Mois : \(home.monthCaption)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
