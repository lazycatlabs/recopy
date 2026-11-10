import Foundation
import Observation

/// Search, type filter, selection and toasts for the clipboard window.
@Observable
final class ClipboardViewModel {
    var query = ""
    var type: TypeFilter?
    var dateFilter = DateFilter.anyTime
    /// Only entries in this group; nil for all.
    var group: UUID?
    /// Shown while ⌘ is held: which entry ⌘1…⌘9 pastes.
    var showsQuickPasteKeys = false
    var selectedID: UUID?
    /// Entries picked with ⌘-click, ⇧-click or ⇧↑↓, to paste together. Empty: only the selected entry.
    var markedIDs: Set<UUID> = []
    /// The note field has the keyboard, so the window's shortcuts leave keys to it.
    var editsNote = false
    /// Where a ⇧ range starts, and the entries the current ⇧ range marked.
    @ObservationIgnored private var anchorID: UUID?
    @ObservationIgnored private var rangeIDs: Set<UUID> = []
    var showsActions = false
    /// The Paste Special sheet for images, text, or a video or audio file, while it's open.
    var pasteSpecial: PasteSpecialModel?
    var textPasteSpecial: TextPasteSpecialModel?
    var mediaPasteSpecial: MediaPasteSpecialModel?
    var showsPasteSpecial: Bool { pasteSpecial != nil || textPasteSpecial != nil || mediaPasteSpecial != nil }
    /// A short confirmation shown at the bottom of the window, e.g. after copying an entry.
    private(set) var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func sections(of session: ClipboardSession, now: Date = .now) -> [(TimeSection, [ClipItem])] {
        let group = session.settings.groups.contains { $0.id == self.group } ? self.group : nil
        let items = ClipUseCases.filter(session.items, type: type, query: query, created: dateFilter, group: group, now: now,
                                        isCode: { session.codeLanguage(of: $0) != nil })
        return ClipUseCases.sections(items, now: now)
    }

    /// The entries in the order they are shown, for keyboard navigation and ⌘1…⌘9.
    func visibleItems(of session: ClipboardSession) -> [ClipItem] {
        sections(of: session).flatMap(\.1)
    }

    func selected(in session: ClipboardSession) -> ClipItem? {
        let visible = visibleItems(of: session)
        return visible.first { $0.id == selectedID } ?? visible.first
    }

    func moveSelection(by offset: Int, in session: ClipboardSession) {
        let visible = visibleItems(of: session)
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selected(in: session)?.id } ?? 0
        selectedID = visible[min(max(current + offset, 0), visible.count - 1)].id
    }

    /// What ↩ pastes: the marked entries in list order, or the selected one.
    func chosen(in session: ClipboardSession) -> [ClipItem] {
        let marked = visibleItems(of: session).filter { markedIDs.contains($0.id) }
        return marked.isEmpty ? selected(in: session).map { [$0] } ?? [] : marked
    }

    /// A click on a row: ⌘ adds or removes it, ⇧ marks the range from where the last click was, a plain click
    /// selects it alone.
    func click(_ id: UUID, command: Bool = false, shift: Bool = false, in session: ClipboardSession) {
        let current = selected(in: session)?.id
        if shift, let anchor = anchorID ?? current { return markRange(from: anchor, to: id, in: session) }
        rangeIDs = []
        anchorID = id
        guard command else {
            markedIDs = []
            selectedID = id
            return
        }
        if markedIDs.isEmpty, let current { markedIDs.insert(current) }
        guard markedIDs.contains(id) else {
            markedIDs.insert(id)
            selectedID = id
            return
        }
        // Unpicking: the selection moves to an entry that's still picked; one left is a plain selection again.
        markedIDs.remove(id)
        selectedID = visibleItems(of: session).first { markedIDs.contains($0.id) }?.id
        anchorID = selectedID
        if markedIDs.count == 1 { markedIDs = [] }
    }

    /// ↑↓ moves the selection; with ⇧ it marks the range from where it started, shrinking when the direction reverses.
    func moveSelection(by offset: Int, extending: Bool, in session: ClipboardSession) {
        guard extending else {
            markedIDs = []
            rangeIDs = []
            anchorID = nil
            return moveSelection(by: offset, in: session)
        }
        let anchor = anchorID ?? selected(in: session)?.id
        moveSelection(by: offset, in: session)
        if let anchor, let selectedID { markRange(from: anchor, to: selectedID, in: session) }
    }

    /// Replaces the previous ⇧ range with the entries from `anchor` to `id`; entries picked with ⌘ stay picked.
    private func markRange(from anchor: UUID, to id: UUID, in session: ClipboardSession) {
        let ids = visibleItems(of: session).map(\.id)
        guard let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: id) else { return }
        markedIDs.subtract(rangeIDs)
        rangeIDs = Set(ids[min(from, to)...max(from, to)])
        markedIDs.formUnion(rangeIDs)
        anchorID = anchor
        selectedID = id
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(Metrics.Panel.toastDuration))
            if !Task.isCancelled { toast = nil }
        }
    }

    func reset() {
        query = ""
        selectedID = nil
        markedIDs = []
        editsNote = false
        rangeIDs = []
        anchorID = nil
        showsActions = false
        pasteSpecial = nil
        textPasteSpecial = nil
        mediaPasteSpecial?.cancel()
        mediaPasteSpecial = nil
        showsQuickPasteKeys = false
        toast = nil
    }
}
