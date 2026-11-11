import Combine
import SwiftUI

extension PastingSettingsPage {
    /// Settings › Pasting › Paste Count and Copy Count: today, this month and since the first one, with the daily average.
    struct StatsSection: View {
        let stats: UsageStats
        let title: String
        /// The accessibility identifier prefix, "pasteStats" or "copyStats".
        let id: String
        /// The footer from the daily average and the first day.
        let footerText: (String, String) -> String
        let emptyText: String
        /// Today, moved on at midnight (also after waking past it), so an open Settings window doesn't keep yesterday's counts.
        @State private var now = Date.now

        var body: some View {
            SettingsGroup(title, footer: footer) {
                HStack(spacing: 0) {
                    tile(stats.today(now), label: L(.pasteStatsToday), id: "today")
                    Divider()
                    tile(stats.thisMonth(now), label: L(.pasteStatsMonth), id: "month")
                    Divider()
                    tile(stats.total, label: L(.pasteStatsTotal), id: "total")
                }
                .padding(.vertical, Spacing.xl)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                now = .now
            }
        }

        private var footer: String {
            guard let first = stats.firstDay else { return emptyText }
            let average = stats.perDay(now).formatted(.number.precision(.fractionLength(0...1)))
            return footerText(average, first.formatted(date: .long, time: .omitted))
        }

        private func tile(_ count: Int, label: String, id tile: String) -> some View {
            VStack(spacing: Spacing.xxs) {
                Text(count.formatted())
                    .font(.scaled(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("settings.\(id).\(tile)")
                Text(label.uppercased())
                    .font(.scaled(.caption, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
