import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// A panel that takes the keyboard without bringing ReCopy to the front, so the app the user was in
/// stays active and can receive the paste (like Spotlight).
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows and hides the clipboard window, handles its keyboard shortcuts and performs the entry actions.
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private let container: AppContainer
    private let model = ClipboardViewModel()
    private var panel: FloatingPanel?
    /// Paste Special's options, opened at the pointer in place of the clipboard window.
    private var specialPanel: FloatingPanel?
    private var keyMonitor: Any?
    /// The app in front when the window opened, which gets the keyboard back when it closes.
    private var previousApp: NSRunningApplication?
    private let guides = PanelGuides()
    /// Where the pointer and the window were when the current drag began.
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    /// Opens Settings and the annotation editor, which live in ordinary windows.
    var showSettings: () -> Void = {}

    init(container: AppContainer) {
        self.container = container
    }

    private var session: ClipboardSession? { container.session }

    /// The clipboard window or Paste Special is on screen.
    private var isOpen: Bool { panel?.isVisible == true || specialPanel?.isVisible == true }

    func toggle() {
        if isOpen { hide() } else { show() }
    }

    /// - Parameters:
    ///   - selecting: the entry to select, e.g. one just made in the annotation editor.
    ///   - toast: a confirmation to show once the window is open.
    func show(selecting id: UUID? = nil, toast: String? = nil) {
        guard let session else { return showSettings() }
        session.pasteboard.checkNow()
        specialPanel?.orderOut(nil)
        if !isOpen {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front == .current ? nil : front
        }
        model.reset()
        model.selectedID = id
        if let toast { model.showToast(toast) }
        Task { await session.reload() }
        let panel = panel ?? makePanel()
        self.panel = panel
        let view = ClipboardPage(model: model) { [weak self] action, item in
            self?.perform(action, on: item)
        } performMany: { [weak self] items in
            if session.settings.pasteDirectly { self?.paste(items) } else { self?.copy(items) }
        } onDrag: { [weak self] ended in
            self?.drag(ended: ended)
        } manageGroups: { [weak self] in
            SettingsNavigation.shared.pane = .groups
            self?.hide(restoringFocus: false)
            self?.showSettings()
        }
        .environment(session)
        panel.contentView = NSHostingView(rootView: view)
        if let visible = Self.screenUnderPointer?.visibleFrame {
            let offset = PanelPlacement.savedOffset ?? PanelPlacement.defaultOffset(in: visible)
            panel.setFrameOrigin(PanelPlacement.origin(size: Metrics.Panel.size, in: visible, offset: offset))
        }
        // ReCopy becomes the active app while the window is open. macOS only lets the active app hand the focus
        // back to another one, so this is what makes `hide()` able to return it to the app the user was in.
        // The forced variant: a plain request is refused for a menu bar app the user isn't in.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        installKeyMonitor()
    }

    /// - Parameter restoringFocus: give the keyboard back to the app the user was in. Off when another
    ///   ReCopy window (Settings, the annotation editor, a save panel) or another app opens next.
    func hide(restoringFocus: Bool = true) {
        guard isOpen else { return }
        guides.hide()
        panel?.orderOut(nil)
        specialPanel?.orderOut(nil)
        model.pasteSpecial = nil
        model.textPasteSpecial = nil
        // Closing stops a video or audio export that's still running.
        model.mediaPasteSpecial?.cancel()
        model.mediaPasteSpecial = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        // Hand the focus back to the app the user was in, so a paste (or ⌘V afterwards) lands in its window
        // without clicking it first. ReCopy is the active app here (see `show`), which macOS requires for this.
        if restoringFocus, let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(from: .current)
        }
        previousApp = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // The clipboard window handing over to Paste Special: keep the previous app and the key monitor.
        if notification.object as? NSWindow === panel, model.showsPasteSpecial { return }
        // Clicking another window: that window takes the focus, so don't pull it back.
        hide(restoringFocus: false)
    }

    private func makePanel(identifier: String = "clipboardPanel") -> FloatingPanel {
        // Borderless, so the SwiftUI content draws the whole rounded shape; the shadow follows it.
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Metrics.Panel.size),
                                  styleMask: [.nonactivatingPanel, .borderless],
                                  backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.hasShadow = true
        // Moved by `drag(ended:)` instead, which snaps to the screen's center.
        panel.isMovableByWindowBackground = false
        panel.setAccessibilityIdentifier(identifier)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.delegate = self
        return panel
    }

    // MARK: Dragging

    private static var screenUnderPointer: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    /// Follows the pointer from where the drag began, snapping to the center lines of the screen it's on,
    /// and remembers the position when the drag ends.
    private func drag(ended: Bool) {
        guard let panel, let visible = Self.screenUnderPointer?.visibleFrame else { return }
        if ended {
            PanelPlacement.save(PanelPlacement.offset(of: panel.frame.origin, size: panel.frame.size, in: visible))
            dragStart = nil
            #if DEBUG
            if E2EMode.keepsGuides { return }
            #endif
            return guides.hide()
        }
        let mouse = NSEvent.mouseLocation
        let start = dragStart ?? (mouse, panel.frame.origin)
        dragStart = start
        let proposed = CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
        let snap = PanelPlacement.snap(proposed, size: panel.frame.size, in: visible, distance: Metrics.Panel.snapDistance)
        panel.setFrameOrigin(snap.origin)
        guides.centeredX = snap.centeredX
        guides.centeredY = snap.centeredY
        guides.show(on: visible, below: panel)
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                // ⌘ alone: show which entries ⌘1…⌘9 paste. Modifier events don't always name a window; this monitor
                // only runs while the window is open.
                if self.panel?.isVisible == true {
                    model.showsQuickPasteKeys = event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
                }
                return event
            }
            guard event.window === self.panel || event.window === self.specialPanel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// ↑↓ select, esc clear or close, ⌘1…9 quick paste, ⌘, Settings, plus the shortcuts set in Settings
    /// (↩ paste, ⌘↩ copy, ⌘K actions, …). Returns whether the key was used.
    private func handle(_ event: NSEvent) -> Bool {
        guard let session else { return false }
        // Typing a note: every key but esc (which leaves the field) goes to it.
        if model.editsNote {
            if Int(event.keyCode) == kVK_Escape { model.editsNote = false; return true }
            return false
        }
        if model.showsPasteSpecial { return handlePasteSpecial(event) }
        let shift = event.modifierFlags.contains(.shift)
        switch Int(event.keyCode) {
        case kVK_DownArrow: model.moveSelection(by: 1, extending: shift, in: session); return true
        case kVK_UpArrow: model.moveSelection(by: -1, extending: shift, in: session); return true
        case kVK_Escape: escape(); return true
        default: break
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           let key = event.charactersIgnoringModifiers {
            if let number = Int(key), (1...Metrics.Panel.quickPasteCount).contains(number) {
                let visible = model.visibleItems(of: session)
                if number <= visible.count { perform(session.settings.pasteDirectly ? .paste : .copy, on: visible[number - 1]) }
                return true
            }
            if key == "," {
                hide(restoringFocus: false)
                showSettings()
                return true
            }
        }
        guard let shortcut = HotKeyStore.shared.shortcut(for: event) else { return false }
        if let selected = model.selected(in: session) { run(shortcut, on: selected, session: session) }
        return true
    }

    /// Paste Special open: esc closes it, the paste and copy shortcuts finish it, the rest go to its controls. While
    /// the code block's language is being searched, keys go to the search (↩ picks) and esc only ends the search.
    private func handlePasteSpecial(_ event: NSEvent) -> Bool {
        if let special = model.textPasteSpecial, special.searchesLanguage {
            guard Int(event.keyCode) == kVK_Escape else { return false }
            special.searchesLanguage = false
            return true
        }
        if Int(event.keyCode) == kVK_Escape { hide(); return true }
        let store = HotKeyStore.shared
        guard store[.paste].matches(event) || store[.copy].matches(event) else { return false }
        finishPasteSpecial(pasting: store[.paste].matches(event))
        return true
    }

    /// esc closes the actions, then clears the marked entries, then the search, then the window.
    private func escape() {
        if model.showsActions {
            model.showsActions = false
        } else if !model.markedIDs.isEmpty {
            model.markedIDs = []
        } else if !model.query.isEmpty {
            model.query = ""
        } else {
            hide()
        }
    }

    private func run(_ shortcut: Shortcut, on selected: ClipItem, session: ClipboardSession) {
        if shortcut == .actions { return model.showsActions.toggle() }
        // ↩ and ⌘↩ use what the footer shows: the picked entries, or the selected one.
        let chosen = model.chosen(in: session)
        if chosen.count > 1, shortcut == .paste || shortcut == .copy {
            return shortcut == .paste ? paste(chosen) : copy(chosen)
        }
        if chosen.count > 1, shortcut == .pasteSpecial { return pasteSpecial(chosen, session: session) }
        let selected = chosen.first ?? selected
        if shortcut == .paste { return perform(session.settings.pasteDirectly ? .paste : .copy, on: selected) }
        if let action = ClipAction.available(for: selected).first(where: { $0.shortcut == shortcut }) {
            perform(action, on: selected)
        }
    }

    // MARK: Actions

    func perform(_ action: ClipAction, on item: ClipItem) {
        guard let session else { return }
        switch action {
        case .paste: paste(item, session: session)
        case .copy: session.copy(item); hide()
        case .pasteSpecial:
            model.showsActions = false
            pasteSpecial([item], session: session)
        case .copyHex: copyColor(item) { $0.hex }
        case .copyRGB: copyColor(item) { $0.rgb }
        case .copyHSL: copyColor(item) { $0.hsl }
        case .open, .composeEmail:
            hide(restoringFocus: false)
            if let url = item.url { NSWorkspace.shared.open(url) }
        case .revealInFinder:
            hide(restoringFocus: false)
            NSWorkspace.shared.activateFileViewerSelecting((item.files ?? []).map { URL(filePath: $0.path) })
        case .annotate: annotate(item, session: session)
        case .saveToFile: save(item, session: session)
        case .pin: session.togglePin(item)
        case .delete:
            model.moveSelection(by: 1, in: session)
            if model.selectedID == item.id { model.moveSelection(by: -1, in: session) }
            session.delete(item)
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// A toast inside the window, for copies made while it's open.
    func showToast(_ message: String) {
        model.showToast(message)
    }

    private func copyColor(_ item: ClipItem, format: (ColorValue) -> String) {
        guard let color = item.color else { return }
        session?.copy(item, as: format(color))
        hide()
    }

    /// Puts the entry on the clipboard, gives the previous app the focus back and sends ⌘V.
    private func paste(_ item: ClipItem, session: ClipboardSession) {
        guard session.settings.pasteDirectly else {
            session.copy(item)
            return hide()
        }
        guard PasteSimulator.isTrusted else {
            session.copy(item)
            hide()
            return PasteSimulator.requestAccess()
        }
        let target = previousApp
        session.preparePaste(item)
        hide()
        pressCommandV(once: target)
    }

    /// The global Paste Special shortcut: the options for the latest copy, at the pointer, if it's an image, an
    /// image file, text, or a video or audio file. Otherwise a toast says so.
    func pasteSpecialLatest() {
        guard let session else { return }
        // The copy just made must be the latest, even if the clipboard wasn't checked since.
        session.pasteboard.checkNow()
        let item = ClipUseCases.latest(session.items)
        let show: () -> Void
        if let item, let source = session.imageURL(of: item) {
            show = { self.showPasteSpecial(PasteSpecialModel(sources: [.init(item: item, url: source)])) }
        } else if let item, item.kind == .text, let text = item.text, !text.isEmpty {
            show = { self.showPasteSpecial(TextPasteSpecialModel(items: [item], text: text)) }
        } else if let item, let media = item.convertibleMedia {
            show = { self.showPasteSpecial(MediaPasteSpecialModel(item: item, url: media.url, kind: media.kind)) }
        } else {
            return ToastPresenter.shared.show(L(.pasteSpecialNoImage))
        }
        if !isOpen {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front == .current ? nil : front
        }
        // Active, so closing can hand the keyboard back to the previous app (see `show`).
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        show()
    }

    /// Paste Special for entries from the list, the dialog matching what they are: images (one or several, converted
    /// together), one text entry, or one video or audio file. Several entries of other kinds, or of mixed kinds, get
    /// a toast instead.
    private func pasteSpecial(_ items: [ClipItem], session: ClipboardSession) {
        let sources = items.compactMap { item in session.imageURL(of: item).map { PasteSpecialModel.Source(item: item, url: $0) } }
        if !sources.isEmpty, sources.count == items.count { return showPasteSpecial(PasteSpecialModel(sources: sources)) }
        if items.count == 1, let item = items.first, let media = item.convertibleMedia {
            return showPasteSpecial(MediaPasteSpecialModel(item: item, url: media.url, kind: media.kind))
        }
        guard items.count == 1, let item = items.first, item.kind == .text, let text = item.text, !text.isEmpty else {
            return model.showToast(L(.pasteSpecialNoImageSelected))
        }
        showPasteSpecial(TextPasteSpecialModel(items: [item], text: text))
    }

    private func showPasteSpecial(_ special: PasteSpecialModel) {
        model.pasteSpecial = special
        present(PasteSpecialPage(model: special, finish: { [weak self] pasting in self?.finishPasteSpecial(pasting: pasting) },
                                 cancel: { [weak self] in self?.hide() }))
    }

    private func showPasteSpecial(_ special: TextPasteSpecialModel) {
        model.textPasteSpecial = special
        present(TextPasteSpecialPage(model: special, finish: { [weak self] pasting in self?.finishPasteSpecial(pasting: pasting) },
                                     cancel: { [weak self] in self?.hide() }))
    }

    /// Swaps the clipboard window for Paste Special's options, with their top-left corner at the pointer.
    private func present(_ view: some View) {
        model.showsActions = false
        let hosting = NSHostingView(rootView: view)
        let panel = specialPanel ?? makePanel(identifier: "pasteSpecialPanel")
        specialPanel = panel
        panel.contentView = hosting
        let size = hosting.fittingSize
        let pointer = NSEvent.mouseLocation
        let visible = Self.screenUnderPointer?.visibleFrame ?? NSRect(origin: pointer, size: size)
        panel.setFrame(NSRect(origin: PanelPlacement.origin(topLeftAt: pointer, size: size, in: visible), size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        // Nothing focused, so ↩ and ⌘↩ finish at once: AppKit would otherwise focus the first text field (the code
        // block's language search).
        panel.makeFirstResponder(nil)
        panel.invalidateShadow()
        guides.hide()
        self.panel?.orderOut(nil)
    }

    /// Puts Paste Special's result on the clipboard (converted images or a converted video or audio file as files, or
    /// the rewritten text) and, when pasting, sends ⌘V to the previous app. A video or audio file is exported first,
    /// with its progress in the sheet.
    /// Paste is offered even with "Paste directly" off, since the user picked it here; without Accessibility it's copied.
    private func finishPasteSpecial(pasting: Bool) {
        guard let session else { return }
        let pastes = pasting && PasteSimulator.isTrusted
        if let special = model.textPasteSpecial {
            session.writeFormatted(special.result, monospaced: special.options.style == .monospaced, for: special.items,
                                   pasting: pastes)
        } else if let special = model.pasteSpecial {
            guard let images = special.converted() else { return ToastPresenter.shared.show(L(.pasteSpecialFailed)) }
            guard session.writeConverted(images, format: special.options.format, for: special.items, pasting: pastes) else { return }
        } else if let special = model.mediaPasteSpecial {
            return special.start { [weak self, weak session] file in
                guard let self, let session, model.mediaPasteSpecial === special,
                      session.writeExported(file, for: special.item, pasting: pastes) else { return }
                closePasteSpecial(pasting: pasting, pastes: pastes)
            }
        } else {
            return
        }
        closePasteSpecial(pasting: pasting, pastes: pastes)
    }

    func copy(_ items: [ClipItem]) {
        session?.copy(items)
        hide()
    }

    /// Pastes several entries in list order: text entries as one text, one per line; with images or files among
    /// them, each entry gets its own ⌘V. Without paste access they're copied instead.
    func paste(_ items: [ClipItem]) {
        guard let session else { return }
        guard session.settings.pasteDirectly, PasteSimulator.isTrusted else {
            copy(items)
            if session.settings.pasteDirectly { PasteSimulator.requestAccess() }
            return
        }
        let target = previousApp
        if let text = ClipUseCases.joinedText(items) {
            session.preparePaste(items, text: text)
            hide()
            return pressCommandV(once: target)
        }
        hide()
        pasteInTurn(items[...], session: session, target: target)
    }

    private func pasteInTurn(_ items: ArraySlice<ClipItem>, session: ClipboardSession, target: NSRunningApplication?,
                             isFirst: Bool = true) {
        guard let item = items.first else { return }
        // The user switched to another app partway through: don't paste the rest there.
        if !isFirst, let target, !target.isActive { return }
        session.preparePaste(item)
        pressCommandV(once: target) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.Clipboard.multiPasteInterval) {
                self.pasteInTurn(items.dropFirst(), session: session, target: target, isFirst: false)
            }
        }
    }

    /// Sends ⌘V once `app` is in front again (checking every few milliseconds, for at most a second), so the
    /// keystroke doesn't reach ReCopy or nowhere while the switch is still under way.
    private func pressCommandV(once app: NSRunningApplication?, attempt: Int = 0, then done: @escaping () -> Void = {}) {
        let isFront = app.map { $0.isActive || $0.isTerminated } ?? true
        guard isFront || attempt >= Metrics.Clipboard.pasteWaitAttempts else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.Clipboard.pasteDelay) {
                self.pressCommandV(once: app, attempt: attempt + 1, then: done)
            }
            return
        }
        // A beat more after the switch, for the app's window to become key.
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.Clipboard.pasteDelay) {
            PasteSimulator.pressCommandV()
            done()
        }
    }

    private func annotate(_ item: ClipItem, session: ClipboardSession) {
        guard let image = session.blobURL(item.blob).flatMap(ImageCache.image) else { return }
        hide(restoringFocus: false)
        MacWindows.show(id: "annotate", title: L(.actionAnnotate), size: Metrics.Annotate.windowSize) {
            AnnotationEditorPage(image: image) { [weak self] png, width, height in
                let saved = session.addImage(png, width: width, height: height)
                MacWindows.close(id: "annotate")
                // Show the result, so it's clear the annotated copy was saved and is on the clipboard. A moment later:
                // closing the editor makes ReCopy a menu bar app again, which would take the keyboard from (and so
                // close) a window opened right now.
                DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.Annotate.reopenDelay) {
                    self?.show(selecting: saved?.id, toast: L(.toastAnnotated))
                }
            } onCopy: { png in
                session.copyImage(png)
                MacWindows.close(id: "annotate")
            } onCancel: {
                MacWindows.close(id: "annotate")
            }
        }
    }

    private func save(_ item: ClipItem, session: ClipboardSession) {
        hide(restoringFocus: false)
        if item.kind == .image, let url = session.blobURL(item.blob), let data = try? Data(contentsOf: url) {
            FileExporter.save(data, name: L(.imageFileName), type: .png)
        } else if let text = item.text {
            FileExporter.save(Data(text.utf8), name: L(.textFileName), type: .plainText)
        }
    }
}

// MARK: Paste Special for video and audio

extension ClipboardPanelController {
    /// Reads the file first (its length, size and sound), so the sheet opens with every option in place.
    private func showPasteSpecial(_ special: MediaPasteSpecialModel) {
        model.mediaPasteSpecial = special
        Task { [weak self] in
            let readable = await special.read()
            guard let self else { return }
            guard readable else {
                if model.mediaPasteSpecial === special { model.mediaPasteSpecial = nil }
                // Opened from the global shortcut with no window to close: give the keyboard back here.
                if !isOpen, let previousApp, !previousApp.isTerminated {
                    NSApp.yieldActivation(to: previousApp)
                    previousApp.activate(from: .current)
                    self.previousApp = nil
                }
                return ToastPresenter.shared.show(L(.pasteSpecialMediaFailed))
            }
            guard model.mediaPasteSpecial === special else { return }
            present(MediaPasteSpecialPage(model: special,
                                          finish: { [weak self] pasting in self?.finishPasteSpecial(pasting: pasting) },
                                          cancel: { [weak self] in self?.hide() }))
        }
    }

    private func closePasteSpecial(pasting: Bool, pastes: Bool) {
        let target = previousApp
        hide()
        if pastes { pressCommandV(once: target) } else if pasting { PasteSimulator.requestAccess() }
    }
}
