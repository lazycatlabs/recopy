import Foundation
import Testing
@testable import ReCopy

struct CleanupCriteriaTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func item(_ text: String, kind: ClipKind = .text, daysAgo: Double, pinned: Bool = false, group: UUID? = nil,
                      note: String? = nil) -> ClipItem {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        var item = ClipItem(kind: kind, text: text, hash: text, firstCopied: date, lastCopied: date)
        item.pinned = pinned
        item.groupID = group
        item.note = note
        return item
    }

    private func texts(_ criteria: CleanupCriteria, in items: [ClipItem]) -> [String] {
        ClipUseCases.matching(items, criteria, now: now, calendar: calendar).compactMap(\.text)
    }

    @Test func defaultsDeleteEverythingButPinned() {
        let items = [item("a", daysAgo: 0), item("b", daysAgo: 400), item("pin", daysAgo: 1, pinned: true)]
        #expect(texts(CleanupCriteria(), in: items) == ["a", "b"])
        #expect(texts(CleanupCriteria(includePinned: true), in: items).count == 3)
    }

    @Test func periodsSplitRecentFromOld() {
        let items = [item("hour", daysAgo: 0.01), item("day", daysAgo: 0.5), item("week", daysAgo: 5),
                     item("month", daysAgo: 20), item("quarter", daysAgo: 60), item("old", daysAgo: 400)]
        #expect(texts(CleanupCriteria(period: .lastHour), in: items) == ["hour"])
        #expect(texts(CleanupCriteria(period: .lastWeek), in: items) == ["hour", "day", "week"])
        #expect(texts(CleanupCriteria(period: .olderThanMonth), in: items) == ["quarter", "old"])
        #expect(texts(CleanupCriteria(period: .olderThanYear), in: items) == ["old"])
    }

    @Test func filtersByKindAndGroup() {
        let work = UUID()
        let items = [item("#FF0000", kind: .color, daysAgo: 1), item("note", daysAgo: 1, group: work), item("x", daysAgo: 1)]
        #expect(texts(CleanupCriteria(kind: .color), in: items) == ["#FF0000"])
        #expect(texts(CleanupCriteria(group: work), in: items) == ["note"])
    }

    @Test func keepsNotedAndGroupedUnlessIncluded() {
        let work = UUID()
        let items = [item("plain", daysAgo: 1), item("noted", daysAgo: 1, note: "keep"),
                     item("grouped", daysAgo: 1, group: work), item("blank", daysAgo: 1, note: "")]
        #expect(texts(CleanupCriteria(), in: items) == ["plain", "blank"])
        #expect(texts(CleanupCriteria(includeNoted: true), in: items) == ["plain", "noted", "blank"])
        #expect(texts(CleanupCriteria(includeGrouped: true), in: items) == ["plain", "grouped", "blank"])
        #expect(texts(CleanupCriteria(group: work), in: items) == ["grouped"])
    }
}
