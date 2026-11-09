import SwiftUI

extension PastingSettingsPage {
    /// Settings › Pasting › Paste Count: pastes today, this month and since the first one, with the daily average.
    struct StatsSection: View {
        private let stats = PasteStats.shared

        var body: some View {
            SettingsGroup(L(.pasteStatsTitle), footer: footer) {
                HStack(spacing: 0) {
                    tile(stats.today(), label: L(.pasteStatsToday), id: "today")
                    Divider()
                    tile(stats.thisMonth(), label: L(.pasteStatsMonth), id: "month")
                    Divider()
                    tile(stats.total, label: L(.pasteStatsTotal), id: "total")
                }
                .padding(.vertical, Spacing.xl)
            }
        }

        private var footer: String {
            guard let first = stats.firstDay else { return L(.pasteStatsEmpty) }
            let average = stats.perDay().formatted(.number.precision(.fractionLength(0...1)))
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
            .accessibilityElement(children: .combine)
        }
    }
}
