import Foundation
import Testing
@testable import ReCopy

struct UsageStatsTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    @Test func countsTodayMonthAndTotal() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stats = UsageStats(key: "test", store: defaults)
        stats.record(at: try date(2026, 10, 30))
        stats.record(at: try date(2026, 11, 1))
        stats.record(at: try date(2026, 11, 9))
        stats.record(at: try date(2026, 11, 9))

        let now = try date(2026, 11, 9)
        #expect(stats.today(now) == 2)
        #expect(stats.thisMonth(now) == 3)
        #expect(stats.total == 4)
        // 30 Oct through 9 Nov is 11 days.
        #expect(stats.perDay(now) == 4.0 / 11)
        // Survives a relaunch.
        #expect(UsageStats(key: "test", store: defaults).total == 4)
    }

    @Test func emptyHasNoAverage() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stats = UsageStats(key: "test", store: defaults)
        #expect(stats.firstDay == nil)
        #expect(stats.perDay() == 0)
    }
}
