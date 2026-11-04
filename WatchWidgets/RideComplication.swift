import SwiftUI
import WidgetKit

@main
struct VirageWatchWidgets: WidgetBundle {
    var body: some Widget {
        RideComplication()
    }
}

/// On the watch face and in the Smart Stack: a shortcut to the app, then the ride once it has started.
struct RideComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RideComplication", provider: RideProvider()) { entry in
            RideComplicationView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Virage")
        .description("Le trajet en cours et le prochain virage.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct RideEntry: TimelineEntry {
    let date: Date
    let state: RideWidgetState
    /// Raised during a ride, so the Smart Stack brings the widget to the top.
    let relevance: TimelineEntryRelevance?
}

struct RideProvider: TimelineProvider {
    func placeholder(in context: Context) -> RideEntry {
        RideEntry(date: .now, state: .preview, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RideEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    /// The Watch app reloads the timeline when the ride changes; nothing to schedule here.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RideEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> RideEntry {
        let state = RideWidgetState.load()
        return RideEntry(date: .now, state: state, relevance: TimelineEntryRelevance(score: state.isRiding ? 100 : 0))
    }
}

private extension RideWidgetState {
    static let preview = RideWidgetState(
        isRiding: true,
        startDate: .now.addingTimeInterval(-1_260),
        distance: "18.4 km",
        navigation: Navigation(symbol: "arrow.turn.up.right", instruction: "Tournez à droite sur la D909", arrival: .now.addingTimeInterval(900))
    )
}

struct RideComplicationView: View {
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
