import Foundation
import Observation

/// How many times the user pasted on this Mac, counted per day and kept in `AppDefaults` as
/// `"2026-11-09": 12`. One small entry per day with a count, so it stays tiny for years.
@Observable
final class UsageStats {
    /// Every ⌘V: the ones ReCopy sends and the ones the user presses in any app.
    static let pastes = UsageStats(key: "pasteCounts")

    private(set) var counts: [String: Int]
    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let storageKey: String

    init(key storageKey: String, store: UserDefaults = AppDefaults.store, calendar: Calendar = .current) {
        self.storageKey = storageKey
        self.store = store
        self.calendar = calendar
        counts = store.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    }

    func record(at date: Date = .now) {
        counts[key(date), default: 0] += 1
        store.set(counts, forKey: storageKey)
    }

    var total: Int { counts.values.reduce(0, +) }

    func today(_ now: Date = .now) -> Int { counts[key(now)] ?? 0 }

    func thisMonth(_ now: Date = .now) -> Int {
        let month = key(now).prefix(7)
        return counts.filter { $0.key.hasPrefix(month) }.values.reduce(0, +)
    }

    /// The first day counted.
    var firstDay: Date? {
        guard let first = counts.keys.min() else { return nil }
        let parts = first.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Average a day from the first day counted through today.
    func perDay(_ now: Date = .now) -> Double {
        guard let firstDay else { return 0 }
        let days = (calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: now)).day ?? 0) + 1
        return Double(total) / Double(max(days, 1))
    }

    private func key(_ date: Date) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}
