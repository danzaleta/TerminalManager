import WidgetKit
import SwiftUI

struct TerminalWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TerminalWidgetEntry {
        TerminalWidgetEntry(
            date: Date(),
            data: WidgetData(
                appsCount: 1,
                packagesCount: 8,
                totalBytes: 933_240_832,
                formattedDiskSpace: "890 MB"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TerminalWidgetEntry) -> Void) {
        let current = WidgetData.load() ?? WidgetData(
            appsCount: 0,
            packagesCount: 0,
            totalBytes: 0,
            formattedDiskSpace: "0 B"
        )
        completion(TerminalWidgetEntry(date: Date(), data: current))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TerminalWidgetEntry>) -> Void) {
        let current = WidgetData.load() ?? WidgetData(
            appsCount: 0,
            packagesCount: 0,
            totalBytes: 0,
            formattedDiskSpace: "0 B"
        )
        let entry = TerminalWidgetEntry(date: Date(), data: current)
        // Refresh every 30 minutes or when app notifies
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct TerminalManagerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Spacer()
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.data.formattedDiskSpace)
                    .font(.system(.title2, design: .rounded))
                    .bold()
                Text("Disk Consumed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("\(entry.data.appsCount + entry.data.packagesCount) items")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.primary)
                Spacer()
                Text(entry.data.lastUpdated, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(NSColor.windowBackgroundColor)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left Column: Total Space
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    Text("Terminal Manager")
                        .font(.headline)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.data.formattedDiskSpace)
                        .font(.system(.largeTitle, design: .rounded))
                        .bold()
                    Text("Total Disk Space")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Right Column: Breakdown
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "macwindow")
                        .foregroundColor(.blue)
                    Text("\(entry.data.appsCount) GUI Apps")
                        .font(.subheadline)
                    Spacer()
                }

                HStack {
                    Image(systemName: "shippingbox.fill")
                        .foregroundColor(.orange)
                    Text("\(entry.data.packagesCount) Formulae")
                        .font(.subheadline)
                    Spacer()
                }

                Spacer()

                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Audited at \(entry.data.lastUpdated, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(NSColor.windowBackgroundColor)
        }
    }
}

@main
struct TerminalManagerWidget: Widget {
    let kind: String = "TerminalManagerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TerminalManagerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Terminal Manager")
        .description("Monitor disk usage and installed packages.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
