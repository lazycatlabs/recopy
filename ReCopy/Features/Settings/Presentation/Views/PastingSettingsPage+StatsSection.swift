import Combine
import SwiftUI

extension PastingSettingsPage {
    /// Settings › Pasting › Paste Count: pastes today, this month and since the first one, with the daily average.
    struct StatsSection: View {
        private let stats = PasteStats.shared
        /// Today, moved on at midnight (also after waking past it), so an open Settings window doesn't keep yesterday's counts.
        @State private var now = Date.now

        var body: some View {
            SettingsGroup(L(.pasteStatsTitle), footer: footer) {
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
            guard let first = stats.firstDay else { return L(.pasteStatsEmpty) }
            let average = stats.perDay(now).formatted(.number.precision(.fractionLength(0...1)))
            return L(.pasteStatsFooter(average, first.formatted(date: .long, time: .omitted)))
        }

        private func tile(_ count: Int, label: String, id: String) -> some View {
            VStack(spacing: Spacing.xxs) {
                Text(count.formatted())
                    .font(.scaled(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("settings.pasteStats.\(id)")
                Text(label.uppercased())
                    .font(.scaled(.caption, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
