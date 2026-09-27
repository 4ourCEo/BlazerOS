import BlazerCore
import SwiftUI
import WidgetKit

/// Home screen and Lock Screen widget showing the last committed scan.
/// Reads directly from the shared App Group journal. It does not scan.
struct JournalWidget: Widget {
    let kind: String = "com.blazer.os.journal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JournalTimelineProvider()) { entry in
            JournalWidgetView(entry: entry)
                .containerBackground(Color(red: 11.0 / 255, green: 15.0 / 255, blue: 23.0 / 255), for: .widget)
        }
        .configurationDisplayName("Last Scan")
        .description("Displays the last committed scan from your desk.")
        .supportedFamilies([
            .systemSmall,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular,
        ])
    }
}

struct JournalWidgetEntry: TimelineEntry {
    var date: Date
    var journal: JournalEntry?
    var stats: OutcomeStats
}

struct JournalTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> JournalWidgetEntry {
        JournalWidgetEntry(
            date: Date(),
            journal: JournalEntry(
                id: "placeholder",
                fingerprint: "CE239CDB",
                pair: "EUR/USD",
                score: 76,
                side: "HIGH",
                verb: "TAP HIGH",
                why: "Completed bars.",
                strike: 1.08692,
                veto: nil,
                scannedAt: Date()
            ),
            stats: OutcomeStats(hits: 4, misses: 1)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (JournalWidgetEntry) -> Void) {
        Task {
            let entry = await loadLatest()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JournalWidgetEntry>) -> Void) {
        Task {
            let entry = await loadLatest()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func loadLatest() async -> JournalWidgetEntry {
        let root = FileLocations.applicationSupport()
        let store = JournalStore(root: root)
        let entries = (try? await store.load()) ?? []
        let ledger = LedgerStore(root: root)
        let stats = (try? await ledger.stats()) ?? .empty
        let sorted = entries.sorted { $0.scannedAt > $1.scannedAt }
        return JournalWidgetEntry(date: Date(), journal: sorted.first, stats: stats)
    }
}

struct JournalWidgetView: View {
    var entry: JournalWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .accessoryRectangular:
            accessoryRectangularView
        case .accessoryInline:
            accessoryInlineView
        case .accessoryCircular:
            accessoryCircularView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BLAZER")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                if let scan = entry.journal {
                    Text(scan.scannedAt, style: .time)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }

            if let scan = entry.journal {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.pair)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(scan.outcome ?? scan.verb)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(verbColor(scan.outcome ?? scan.verb))
                }
                .padding(.top, 2)

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline) {
                    Text("\(scan.score)")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Strike")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text(PriceFormat.px(scan.strike))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
            } else {
                Spacer()
                Text("No scans committed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
            }
        }
        .padding(4)
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let scan = entry.journal {
                HStack {
                    Text(scan.pair)
                        .font(.headline)
                    Spacer()
                    Text("\(scan.score)")
                        .font(.headline)
                }
                Text(scan.outcome ?? scan.verb)
                    .font(.subheadline)
                    .foregroundStyle(verbColor(scan.outcome ?? scan.verb))
                Text("Strike \(PriceFormat.px(scan.strike))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Blazer")
                    .font(.headline)
                Text("No scans")
                    .font(.caption)
            }
        }
    }

    private var accessoryInlineView: some View {
        if let scan = entry.journal {
            Text("\(scan.pair) \(scan.outcome ?? scan.verb) (\(scan.score))")
        } else {
            Text("Blazer: Ready")
        }
    }

    private var accessoryCircularView: some View {
        ZStack {
            if let scan = entry.journal {
                VStack(spacing: 0) {
                    Text(scan.pair.prefix(3))
                        .font(.system(size: 9, weight: .bold))
                    Text("\(scan.score)")
                        .font(.system(size: 15, weight: .semibold))
                }
            } else {
                Text("B")
                    .font(.title2.weight(.bold))
            }
        }
    }

    private func verbColor(_ verb: String) -> Color {
        switch verb {
        case "TAP HIGH", "HIT":
            return Color(red: 46.0 / 255, green: 204.0 / 255, blue: 113.0 / 255)
        case "TAP LOW", "MISS":
            return Color(red: 231.0 / 255, green: 76.0 / 255, blue: 60.0 / 255)
        default:
            return Color.white.opacity(0.6)
        }
    }
}

@main
struct BlazerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JournalWidget()
    }
}
