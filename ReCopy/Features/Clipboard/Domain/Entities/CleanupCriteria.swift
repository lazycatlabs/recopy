import Foundation

/// Which entries Settings › History › Delete Entries removes, by when they were last copied.
nonisolated enum CleanupPeriod: String, CaseIterable, Identifiable, Sendable {
    case anyTime, lastHour, lastDay, lastWeek, lastMonth, olderThanWeek, olderThanMonth, olderThanThreeMonths, olderThanYear

    var id: Self { self }

    /// Whether an entry last copied at `date` falls in the period.
    func contains(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .anyTime: true
        case .lastHour: date >= now.addingTimeInterval(-3_600)
        case .lastDay: date >= now.addingTimeInterval(-86_400)
        case .lastWeek: date >= calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .lastMonth: date >= calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .olderThanWeek: date < calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .olderThanMonth: date < calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .olderThanThreeMonths: date < calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .olderThanYear: date < calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }

    var title: String {
        switch self {
        case .anyTime: L(.cleanupAnyTime)
        case .lastHour: L(.cleanupLastHour)
        case .lastDay: L(.cleanupLastDay)
        case .lastWeek: L(.cleanupLastWeek)
        case .lastMonth: L(.cleanupLastMonth)
        case .olderThanWeek: L(.cleanupOlderThanWeek)
        case .olderThanMonth: L(.cleanupOlderThanMonth)
        case .olderThanThreeMonths: L(.cleanupOlderThanThreeMonths)
        case .olderThanYear: L(.cleanupOlderThanYear)
        }
    }

    /// Where the menu puts a separator: between "in the last …" and "older than …".
    var startsOlderSection: Bool { self == .olderThanWeek }
}

/// The filters for deleting entries in bulk. By default pinned entries, entries with a note and entries in a group are kept.
nonisolated struct CleanupCriteria: Equatable, Sendable {
    var period = CleanupPeriod.anyTime
    /// Only this kind; nil for all.
    var kind: ClipKind?
    /// Only entries in this group; nil for all.
    var group: UUID?
    var includePinned = false
    var includeNoted = false
    /// Ignored when `group` is set: picking a group includes its entries.
    var includeGrouped = false
}

extension ClipUseCases {
    /// The entries `criteria` would delete.
    static func matching(_ items: [ClipItem], _ criteria: CleanupCriteria, now: Date = .now,
                         calendar: Calendar = .current) -> [ClipItem] {
        items.filter { item in
            (criteria.includePinned || !item.pinned)
                && (criteria.kind == nil || item.kind == criteria.kind)
                && (criteria.includeNoted || (item.note ?? "").isEmpty)
                && (criteria.group.map { item.groupID == $0 } ?? (criteria.includeGrouped || item.groupID == nil))
                && criteria.period.contains(item.lastCopied, now: now, calendar: calendar)
        }
    }
}
