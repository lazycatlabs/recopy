import AppKit
import XCTest

/// End-to-end tests: launch the real app (in its `-e2e` mode: a throwaway vault with sample entries, a private
/// clipboard and separate preferences) and use it as a person would. Each test saves screenshots of what it checks.
///
/// Run with `scripts/e2e.sh`, which also collects the screenshots into `e2e-output/` (ignored by git).
final class ReCopyE2ETests: XCTestCase {
    private var app: XCUIApplication!
    private let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
    private let timeout: TimeInterval = 10

    override func setUp() {
        continueAfterFailure = false
        // Connects the runner to the window server. Without it, the first element screenshot in a fresh runner
        // aborts in CoreGraphics (CGS_REQUIRE_INIT) when more than one display is attached.
        _ = NSScreen.screens
    }

    override func tearDown() {
        app?.terminate()
    }

    // MARK: Clipboard window

    func test01PanelHasNewLookAndAnyDayFilter() {
        launch(open: "panel:image")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        XCTAssertEqual(element("panel.dateFilter").title, "Any Day", "Date filter reads “Any Day”")
        XCTAssertEqual(element("panel.search").placeholderValue, "Search your clipboard")
        XCTAssertTrue(panel.staticTexts["Pinned"].exists)
        XCTAssertTrue(panel.staticTexts["Today"].exists)
        XCTAssertTrue(panel.staticTexts["1440 × 900"].exists, "Info table shows the image size")
        screenshot(panel, "01-panel-new-look")

        element("panel.dateFilter").click()
        XCTAssertTrue(app.menuItems["Any Day"].waitForExistence(timeout: timeout))
        screenshotAroundPanel("02-date-filter-any-day")
        app.typeKey(.escape, modifierFlags: [])
    }

    func test02ActionsMenuShowsKeyCaps() {
        launch(open: "panel:image")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        XCTAssertEqual(element("panel.actions").label, "Actions, ⌘, K", "Footer shows ⌘ K as separate key caps")
        panel.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("panel.actionsMenu").waitForExistence(timeout: timeout))
        XCTAssertTrue(element("panel.actionsMenu").buttons["Annotate, ⌘, E"].exists, "Annotate shows its ⌘ E key caps")
        screenshot(panel, "03-actions-menu-key-caps")
    }

    func test03PanelDragsAndSnapsToScreenCenter() throws {
        launch(open: "panel", extra: ["-e2eGuides"])
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        let start = panel.frame
        let screen = try XCTUnwrap(visibleFrame(containing: start))

        // Away from the center: the window follows the pointer.
        drag(by: CGVector(dx: -220, dy: 140))
        let moved = panel.frame
        XCTAssertEqual(moved.minX, start.minX - 220, accuracy: 2)
        XCTAssertEqual(moved.minY, start.minY + 140, accuracy: 2)

        // Close to the center: the window snaps onto both center lines.
        let target = CGPoint(x: screen.midX + 9, y: screen.midY - 7)
        drag(by: CGVector(dx: target.x - moved.midX, dy: target.y - moved.midY))
        let snapped = panel.frame
        XCTAssertEqual(snapped.midX, screen.midX, accuracy: 1)
        XCTAssertEqual(snapped.midY, screen.midY, accuracy: 1)
        screenshotAroundPanel("04-panel-snapped-to-center-with-guides")

        // The position is remembered the next time the window opens.
        app.terminate()
        launch(open: "panel", keepDefaults: true)
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        XCTAssertEqual(panel.frame.midX, screen.midX, accuracy: 1)
        XCTAssertEqual(panel.frame.midY, screen.midY, accuracy: 1)
    }

    func test04ClosingPanelGivesFocusBack() {
        launch()
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: timeout))
        send("panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        panel.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !self.element("panel.search").exists })
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: timeout), "The app the user was in is in front again")
    }

    // MARK: Settings

    func test05SettingsOpensFocused() {
        launch()
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: timeout))
        send("settings")
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout), "Settings comes to the front")
        screenshot(app.windows["settings"], "06-settings-focused")
    }

    func test06ShortcutsCanBeChangedInSettings() {
        launch(open: "settings")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        openSettingsPage("shortcuts", in: settings)
        let actions = settings.buttons["settings.shortcut.actions"]
        reveal(actions, in: settings)
        XCTAssertEqual(actions.title.isEmpty ? actions.label : actions.title, "⌘K")
        XCTAssertTrue(settings.buttons["settings.shortcut.openHistory"].exists)
        screenshot(settings, "07-settings-shortcuts")

        actions.click()
        settings.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(waitUntil { (actions.title.isEmpty ? actions.label : actions.title) == "⌘J" }, "Recorded ⌘J")
        screenshot(settings, "08-settings-shortcut-changed")

        send("panel:image")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        XCTAssertEqual(element("panel.actions").label, "Actions, ⌘, J", "Footer shows the new keys")
        panel.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(element("panel.actionsMenu").waitForExistence(timeout: timeout), "⌘J opens Actions")
        screenshot(panel, "09-custom-shortcut-opens-actions")
    }

    // MARK: Annotate

    func test07AnnotateOpensFocused() {
        launch()
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: timeout))
        send("annotate")
        XCTAssertTrue(app.windows["annotate"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout), "The annotation editor comes to the front")
        screenshot(app.windows["annotate"], "10-annotate-focused")
    }

    func test08AnnotateAddsText() {
        launch(open: "annotate")
        let editor = app.windows["annotate"]
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        let textTool = editor.radioButtons["Text"]
        XCTAssertTrue(textTool.waitForExistence(timeout: timeout))
        textTool.click()

        let canvas = element("annotate.canvas")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.62)).click()
        let field = element("annotate.text")
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        app.typeText("Best quarter yet!")
        XCTAssertEqual(field.value as? String, "Best quarter yet!")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { !field.exists }, "↩ keeps the text on the image")
        XCTAssertTrue(editor.exists, "↩ doesn't close the editor while typing")
        screenshot(editor, "11-annotate-text-added")

        editor.buttons["Save as New Entry"].click()
        let toast = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN {'panel.toast', 'toast'}")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: timeout), "The annotated copy is saved")
        screenshot(panel, "12-annotated-image-saved")
    }

    func test09AnnotateCopiesToClipboard() {
        let clipboard = NSPasteboard(name: NSPasteboard.Name("com.lazycatlabs.recopy.e2e"))
        clipboard.clearContents()
        launch(open: "annotate")
        let editor = app.windows["annotate"]
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        editor.radioButtons["Rectangle"].click()
        let canvas = element("annotate.canvas")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05))
            .click(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        screenshot(editor, "13-annotate-copy-button")

        element("annotate.copy").click()
        XCTAssertTrue(waitUntil { !editor.exists }, "Copying closes the editor")
        XCTAssertTrue(waitUntil { NSImage(pasteboard: clipboard) != nil }, "The edited image is on the clipboard")
        if let image = NSImage(pasteboard: clipboard) {
            let attachment = XCTAttachment(image: image)
            attachment.name = "14-copied-annotated-image"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func test09bAnnotateMovesAndResizesMarks() {
        launch(open: "annotate")
        let editor = app.windows["annotate"]
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        let canvas = element("annotate.canvas")
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { canvas.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        editor.radioButtons["Rectangle"].click()
        point(0.1, 0.1).click(forDuration: 0.1, thenDragTo: point(0.3, 0.3))

        editor.radioButtons["Select, move and resize"].click()
        // Pressing inside the rectangle selects it and drags it; then its bottom-right handle stretches it.
        point(0.2, 0.2).click(forDuration: 0.1, thenDragTo: point(0.5, 0.5))
        point(0.6, 0.6).click(forDuration: 0.1, thenDragTo: point(0.85, 0.8))
        XCTAssertTrue(editor.buttons["Undo"].isEnabled, "Moving and resizing can be undone")
        screenshot(editor, "14b-annotate-moved-resized")
    }

    // MARK: Quick paste, groups, Settings pages

    func test10HoldingCommandShowsQuickPasteKeys() {
        launch(open: "panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        XCTAssertFalse(element("row.quickKey").exists)
        // XCUITest's own modifier holding doesn't send the ⌘ key-down the app listens for, so it's sent through the app.
        send("command:down")
        XCTAssertTrue(element("row.quickKey").waitForExistence(timeout: timeout), "⌘ shows ⌘1…⌘9 on the rows")
        // Ten sample entries: the first nine get ⌘1…⌘9.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "row.quickKey").count, 9)
        screenshot(panel, "15-hold-command-quick-paste-keys")
        send("command:up")
        XCTAssertTrue(waitUntil { !self.element("row.quickKey").exists }, "Releasing ⌘ hides them")
    }

    func test11GroupsFilterAndAssign() {
        launch(open: "panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        let rows = { self.panel.scrollViews.firstMatch.staticTexts.count }
        let all = rows()

        // Filter by the "Work" group: only its two entries are left.
        element("panel.groupFilter").click()
        app.menuItems["Work"].click()
        XCTAssertEqual(element("panel.groupFilter").title, "Work")
        XCTAssertTrue(waitUntil { rows() < all })
        XCTAssertTrue(panel.staticTexts["Work"].exists, "Entries show their group")
        screenshot(panel, "16-groups-filtered-by-work")

        // Back to all, then put the selected entry in "Design" from Actions (⌘K).
        element("panel.groupFilter").click()
        app.menuItems["All Groups"].click()
        panel.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("panel.actionsGroup").waitForExistence(timeout: timeout))
        screenshot(panel, "17-groups-in-actions-menu")
        element("panel.actionsGroup").click()
        app.menuItems["Design"].click()
        XCTAssertTrue(waitUntil { self.panel.staticTexts["Design"].exists }, "The entry is now in Design")
        screenshot(panel, "18-entry-added-to-design")
    }

    func test12SettingsSidebarPagesAndSearch() {
        launch(open: "settings")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        XCTAssertTrue(element("settings.page.general").waitForExistence(timeout: timeout))
        screenshot(settings, "19-settings-general")

        openSettingsPage("appearance", in: settings)
        XCTAssertTrue(app.buttons["settings.centerWindow"].exists, "Window position can be reset")
        screenshot(settings, "20-settings-appearance")

        openSettingsPage("groups", in: settings)
        XCTAssertEqual(settings.textFields.matching(identifier: "settings.groupName").count, 2)
        settings.buttons["settings.addGroup"].click()
        XCTAssertTrue(waitUntil { settings.textFields.matching(identifier: "settings.groupName").count == 3 }, "Add Group adds one")
        screenshot(settings, "21-settings-groups")

        // Searching for a setting opens the page it's on.
        let search = settings.searchFields.firstMatch
        search.click()
        search.typeText("sound")
        XCTAssertTrue(element("settings.page.pasting").waitForExistence(timeout: timeout), "“sound” finds Pasting")
        screenshot(settings, "22-settings-search")
    }

    func test13UpdatesAndChangelogInSettings() {
        launch(open: "settings")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        openSettingsPage("updates", in: settings)
        // E2E runs see a sample 9.9.0 release instead of the network.
        XCTAssertTrue(settings.buttons["settings.updateDownload"].waitForExistence(timeout: timeout), "A newer version offers Download")
        XCTAssertTrue(element("settings.release.9.9.0").exists, "The changelog lists the new version")
        XCTAssertTrue(element("settings.release.0.1.1").exists, "…and the installed one")
        screenshot(settings, "23-settings-updates-changelog")
    }

    func test14StorageAndDeletingEntriesByType() {
        launch(open: "settings")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        openSettingsPage("history", in: settings)

        let storage = element("settings.storageUsed")
        reveal(storage, in: settings)
        XCTAssertTrue(waitUntil { storage.value as? String != "Calculating…" && (storage.value as? String)?.contains("B") == true },
                      "Shows the space the history takes")

        // Only colours: the two sample colours match.
        let type = settings.popUpButtons["settings.cleanupType"]
        reveal(type, in: settings)
        type.click()
        app.menuItems["Color"].click()
        let matches = element("settings.cleanupMatches")
        reveal(matches, in: settings)
        XCTAssertTrue(settings.staticTexts["2 entries match"].waitForExistence(timeout: timeout), "Two colours match")
        screenshot(settings, "24-settings-storage-and-delete")

        settings.buttons["settings.cleanupDelete"].click()
        // The confirmation's button, in the Settings window (the Touch Bar has one with the same name).
        let confirm = settings.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.click()
        XCTAssertTrue(settings.staticTexts["0 entries match"].waitForExistence(timeout: timeout), "The colours are gone")

        send("panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        XCTAssertFalse(panel.staticTexts["#FF8C3C"].exists, "Deleted entries leave the history")
    }

    func test14bPasteCountShowsTodayMonthAndAllTime() {
        launch(open: "settings")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        openSettingsPage("pasting", in: settings)

        // Seeded by E2EFixtures: two pastes today, one 40 days ago.
        let today = element("settings.pasteStats.today")
        reveal(today, in: settings)
        XCTAssertEqual(today.value as? String, "2", "Today counts today's pastes")
        XCTAssertEqual(element("settings.pasteStats.month").value as? String, "2", "This month leaves out last month's")
        XCTAssertEqual(element("settings.pasteStats.total").value as? String, "3", "All time counts every paste")
        // 3 pastes over 41 days.
        let average = "0.1 pastes a day on average since"
        let footer = settings.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", average, average))
        XCTAssertTrue(footer.firstMatch.exists, "The footer shows the daily average since the first paste")
        screenshot(settings, "24b-settings-paste-count")

        send("recordPaste")
        XCTAssertTrue(waitUntil { today.value as? String == "3" }, "A new paste shows up at once")
        XCTAssertEqual(element("settings.pasteStats.total").value as? String, "4")
    }

    func test15SelectingSeveralEntriesPastesThemTogether() {
        launch(open: "panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        // Holding ⌘ shows the quick-paste keys, which renames the rows "row.quickKey".
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'row'"))
        rows.element(boundBy: 0).click()
        XCUIElement.perform(withKeyModifiers: .command) { rows.element(boundBy: 2).click() }
        XCTAssertTrue(waitUntil { self.element("panel.primary").label.contains("2 Entries") }, "⌘-click adds a second entry")
        screenshot(panel, "25-two-entries-selected")

        XCUIElement.perform(withKeyModifiers: .shift) { rows.element(boundBy: 4).click() }
        XCTAssertTrue(waitUntil { self.element("panel.primary").label.contains("4 Entries") }, "⇧-click selects the range")
        screenshot(panel, "26-range-selected")

        panel.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !self.element("panel.primary").label.contains("Entries") }, "esc clears the selection")
    }

    func test16NotesAreSavedAndSearchable() {
        launch(open: "panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        let note = element("panel.note")
        XCTAssertTrue(note.waitForExistence(timeout: timeout))
        note.click()
        note.typeText("quarterly invoice")
        screenshot(panel, "27-note-added")

        // esc leaves the note for the search field.
        panel.typeKey(.escape, modifierFlags: [])
        panel.typeText("quarterly")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'row'"))
        XCTAssertTrue(waitUntil { rows.count == 1 }, "Searching finds the entry by its note")
        screenshot(panel, "28-note-found-by-search")
        // The row's texts are combined into its accessibility value.
        XCTAssertTrue(waitUntil { (rows.firstMatch.value as? String)?.contains("quarterly invoice") == true },
                      "The row shows the matching note")
    }

    // MARK: Welcome

    func test17OnboardingShowsOnceBeforeVaultPicker() {
        launch(open: "welcome")
        let welcome = app.windows["welcome"]
        XCTAssertTrue(welcome.waitForExistence(timeout: timeout))
        XCTAssertTrue(element("onboarding.page.welcome").waitForExistence(timeout: timeout), "First launch shows the introduction")
        XCTAssertTrue(welcome.staticTexts["Welcome to ReCopy"].exists)
        XCTAssertTrue(element("onboarding.credit").exists, "The introduction credits Lazycatlabs")
        XCTAssertFalse(element("vault.choose").exists)
        screenshot(welcome, "29-onboarding-welcome")

        // The shortcut page lights its key caps when the shortcut is pressed.
        element("onboarding.next").click()
        XCTAssertTrue(element("onboarding.page.shortcut").waitForExistence(timeout: timeout))
        welcome.typeKey("v", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("onboarding.shortcutDone").waitForExistence(timeout: timeout), "Trying the shortcut is confirmed")
        screenshot(welcome, "30-onboarding-shortcut-tried")

        // → turns the page too.
        welcome.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(element("onboarding.page.sync").waitForExistence(timeout: timeout), "→ goes to the next page")
        screenshot(welcome, "31-onboarding-sync")
        element("onboarding.next").click()
        XCTAssertTrue(element("onboarding.page.organize").waitForExistence(timeout: timeout))
        screenshot(welcome, "32-onboarding-organize")

        element("onboarding.start").click()
        XCTAssertTrue(element("vault.choose").waitForExistence(timeout: timeout), "Get Started leads to the folder picker")
        XCTAssertTrue(element("onboarding.credit").exists)
        screenshot(welcome, "33-onboarding-vault-picker")

        // Seen once: the next welcome window goes straight to the folder picker.
        app.terminate()
        launch(open: "welcome", keepDefaults: true)
        XCTAssertTrue(element("vault.choose").waitForExistence(timeout: timeout))
        XCTAssertFalse(element("onboarding.page.welcome").exists, "The introduction isn't shown again")
    }

    func test18AboutShowsTheLicense() {
        launch(open: "settings")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        openSettingsPage("about", in: settings)
        XCTAssertTrue(element("settings.license").waitForExistence(timeout: timeout), "About links to the GPL-3.0 license")
        XCTAssertTrue(element("settings.sponsor").exists, "About links to GitHub Sponsors")
        XCTAssertTrue(element("settings.sponsor.saweria").exists, "About lists every sponsor platform")
        screenshot(settings, "34-settings-about-license")
    }

    func test19AnnotateShapesSizeAndBlur() {
        launch(open: "annotate")
        let editor = app.windows["annotate"]
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        let canvas = element("annotate.canvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: timeout))
        var marks = 0
        func drag(from start: CGVector, to end: CGVector) {
            canvas.coordinate(withNormalizedOffset: start)
                .click(forDuration: 0.2, thenDragTo: canvas.coordinate(withNormalizedOffset: end))
            marks += 1
            XCTAssertTrue(editor.buttons["Undo"].isEnabled, "Mark \(marks) is drawn")
        }

        editor.radioButtons["Blur"].click()
        element("annotate.size").coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()
        drag(from: CGVector(dx: 0.05, dy: 0.05), to: CGVector(dx: 0.45, dy: 0.3))

        editor.radioButtons["Circle"].click()
        XCTAssertTrue(editor.radioButtons["Fill"].waitForExistence(timeout: timeout), "Shapes can be filled")
        editor.radioButtons["Fill"].click()
        drag(from: CGVector(dx: 0.55, dy: 0.1), to: CGVector(dx: 0.75, dy: 0.35))

        editor.radioButtons["Border"].click()
        element("annotate.size").coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()
        editor.radioButtons["Triangle"].click()
        drag(from: CGVector(dx: 0.6, dy: 0.5), to: CGVector(dx: 0.9, dy: 0.9))

        editor.radioButtons["Pen"].click()
        XCTAssertFalse(editor.radioButtons["Fill"].exists, "Fill is only offered for shapes")
        screenshot(editor, "35-annotate-shapes-size-blur")
    }

    // MARK: Paste Special

    func test20PasteSpecialShortcutOpensLatestImageAtPointer() throws {
        let point = parkPointer()
        let png = try Data(contentsOf: samplePNG())
        copyInApp { $0.setData(png, forType: .png) }
        send("pasteSpecial")

        let special = element("pasteSpecialPanel")
        XCTAssertTrue(special.waitForExistence(timeout: timeout), "The shortcut opens Paste Special for the copied image")
        XCTAssertFalse(element("panel.search").exists, "Without opening the clipboard window")
        XCTAssertEqual(special.frame.minX, point.x, accuracy: 2, "Opens at the pointer")
        XCTAssertEqual(special.frame.minY, point.y, accuracy: 2, "Opens at the pointer")
        XCTAssertTrue(element("pasteSpecial.paste").exists, "Paste is always offered")
        screenshot(special, "36-paste-special-at-pointer")

        // HEIC at half size: the 800 × 500 image becomes 400 × 250.
        pick("HEIC", in: special)
        pick("50%", in: special)
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.summary")).contains("400×250") }, "The preview shows the new size")
        screenshot(special, "37-paste-special-heic-half-size")

        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitUntil { !special.exists }, "⌘↩ copies and closes")
        XCTAssertTrue(waitUntil { self.copiedFiles().first?.pathExtension == "heic" }, "A HEIC file is on the clipboard")
        let image = try XCTUnwrap(copiedFiles().first.flatMap(NSImage.init(contentsOf:)))
        XCTAssertEqual(image.representations.first?.pixelsWide, 400)
        let attachment = XCTAttachment(image: image)
        attachment.name = "38-paste-special-copied-heic"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test20bPasteSpecialConvertsACopiedImageFileToSVGAndPDF() {
        _ = parkPointer()
        send("copy:imageFile")
        // Recorded on the app's next clipboard check.
        RunLoop.current.run(until: .now.addingTimeInterval(1.5))
        for format in ["SVG", "PDF"] {
            send("pasteSpecial")
            let special = element("pasteSpecialPanel")
            XCTAssertTrue(special.waitForExistence(timeout: timeout), "The shortcut opens Paste Special for the copied file")
            pick(format, in: special)
            XCTAssertFalse(element("pasteSpecial.quality").isEnabled, "\(format) has no quality setting")
            XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.summary")).contains("1440×900") },
                          "Preview: \(text(of: element("pasteSpecial.summary")))")
            screenshot(special, "40-paste-special-file-to-\(format.lowercased())")
            app.typeKey(.return, modifierFlags: .command)
            XCTAssertTrue(waitUntil { !special.exists })
            XCTAssertTrue(waitUntil { self.copiedFiles().first?.pathExtension == format.lowercased() }, "A \(format) file is on the clipboard")
            XCTAssertEqual(copiedFiles().first?.deletingPathExtension().lastPathComponent, "Sample", "Named after the copied file")
        }
    }

    func test20cPasteSpecialSaysWhenTheLatestCopyIsNotAnImage() {
        // The sample history's latest entry is a link.
        launch()
        send("pasteSpecial")
        let toast = element("toast")
        XCTAssertTrue(toast.waitForExistence(timeout: timeout), "A toast explains why nothing opened")
        XCTAssertTrue(text(of: toast).contains("isn’t an image") || toast.staticTexts["The last copy isn’t an image"].exists)
        XCTAssertFalse(element("pasteSpecialPanel").exists)
        screenshot(toast, "41-paste-special-not-an-image")
    }

    func test20hPasteSpecialFormatsCopiedJSON() {
        _ = parkPointer()
        copyInApp { $0.setString(#"{"name":"ReCopy","tags":["clipboard","mac"]}"#, forType: .string) }
        send("pasteSpecial")

        let special = element("pasteSpecialPanel")
        XCTAssertTrue(special.waitForExistence(timeout: timeout), "The shortcut opens Paste Special for copied text")
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.detected")).contains("JSON") }, "Detected as JSON")
        screenshot(special, "44-paste-special-json")

        pick("Code Block", in: special)
        screenshot(special, "45-paste-special-json-code-block")
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitUntil { !special.exists }, "⌘↩ copies and closes")
        let expected = "```json\n{\n  \"name\": \"ReCopy\",\n  \"tags\": [\n    \"clipboard\",\n    \"mac\"\n  ]\n}\n```"
        XCTAssertTrue(waitUntil { self.clipboard.string(forType: .string) == expected },
                      "Indented JSON in a code fence: \(clipboard.string(forType: .string) ?? "nothing")")
    }

    func test20fCodeFilterMarksCodeAndOpensTextPasteSpecial() {
        launch(open: "panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'row'"))
        let codeRows = app.descendants(matching: .any).matching(identifier: "row.code")
        XCTAssertTrue(waitUntil { codeRows.count == 3 }, "The brew command, the Swift snippet and the JSON are marked as code")
        screenshot(panel, "46-code-badges-in-list")

        // Code: the pinned brew command, the Swift snippet and the JSON, but not the other text.
        element("panel.filter").click()
        app.menuItems["Code"].click()
        XCTAssertTrue(waitUntil { rows.count == 3 }, "Only code entries: \(rows.count)")
        XCTAssertTrue(text(of: element("panel.filter")).contains("Code"))
        screenshot(panel, "47-code-filter")

        // ⌥↩ on code opens the text dialog, with the same shortcut as for images.
        // The pinned brew command is selected; the Swift snippet is next.
        panel.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: .option)
        let special = element("pasteSpecialPanel")
        XCTAssertTrue(special.waitForExistence(timeout: timeout), "⌥↩ opens Paste Special for the selected code")
        screenshot(special, "48-paste-special-swift-code-block")
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.detected")).contains("Swift") },
                      "Detected as Swift: \(text(of: element("pasteSpecial.detected")))")
        XCTAssertFalse(element("pasteSpecial.format").exists, "The text dialog, not the image one")

        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitUntil { !special.exists }, "⌘↩ copies and closes")
        XCTAssertTrue(waitUntil { self.clipboard.string(forType: .string)?.hasPrefix("```swift\nstruct ContentView") == true },
                      "A Swift code block: \(clipboard.string(forType: .string) ?? "nothing")")
    }

    func test20gPasteSpecialRefusesSeveralEntriesOfMixedKinds() {
        launch(open: "panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        row(containing: "Image (").click()
        XCUIElement.perform(withKeyModifiers: .command) {
            self.row(containing: "ContentView").click()
        }
        XCTAssertTrue(waitUntil { self.element("panel.primary").label.contains("2 Entries") })
        app.typeKey(.return, modifierFlags: .option)

        let toast = element("panel.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: timeout), "A toast explains why nothing opened")
        XCTAssertTrue(waitUntil { self.text(of: toast).contains("several images") || toast.staticTexts.count > 0 })
        XCTAssertFalse(element("pasteSpecialPanel").exists, "No dialog for an image and a text together")
        screenshot(panel, "49-paste-special-mixed-selection")
    }

    func test20iCodeBlockLanguageCanBeSearched() {
        _ = parkPointer()
        copyInApp { $0.setString("puts 'Hello, ReCopy'", forType: .string) }
        send("pasteSpecial")

        let special = element("pasteSpecialPanel")
        XCTAssertTrue(special.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.detected")) == "Plain text" }, "No language detected")
        pick("Code Block", in: special)
        let language = element("pasteSpecial.language")
        XCTAssertEqual(text(of: language), "None", "No language until one is picked")
        language.click()
        let options = app.descendants(matching: .any).matching(identifier: "pasteSpecial.languageOption")
        XCTAssertTrue(waitUntil { options.count > 1 }, "Clicking the field lists the languages")
        special.typeText("rub")
        XCTAssertTrue(waitUntil { options.count == 1 }, "Only Ruby matches: \(options.count), field: \(text(of: language))")
        screenshot(special, "50-paste-special-language-search")

        special.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.language")).contains("Ruby") }, "↩ picks Ruby")
        XCTAssertTrue(special.exists, "↩ in the search picks a language instead of pasting")
        screenshot(special, "51-paste-special-ruby-code-block")

        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitUntil { !special.exists }, "⌘↩ copies and closes")
        XCTAssertTrue(waitUntil { self.clipboard.string(forType: .string) == "```ruby\nputs 'Hello, ReCopy'\n```" },
                      "A Ruby code block: \(clipboard.string(forType: .string) ?? "nothing")")
    }

    func test20jCopyButtonCopiesTheCodeBlock() {
        _ = parkPointer()
        copyInApp { $0.setString("targets:\n  $default:\n    builders:\n      enabled: true", forType: .string) }
        send("pasteSpecial")
        let special = element("pasteSpecialPanel")
        XCTAssertTrue(special.waitForExistence(timeout: timeout))
        pick("Code Block", in: special)
        element("pasteSpecial.language").click()
        special.typeText("yaml")
        special.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.language")).contains("YAML") })

        element("pasteSpecial.copy").click()
        XCTAssertTrue(waitUntil { !special.exists }, "Copy closes")
        let expected = "```yaml\ntargets:\n  $default:\n    builders:\n      enabled: true\n```"
        XCTAssertTrue(waitUntil { self.clipboard.string(forType: .string) == expected },
                      "The code block is copied: \(clipboard.string(forType: .string) ?? "nothing")")

        // It's in the history too, as the latest entry, tagged YAML.
        send("panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        XCTAssertTrue(row(containing: "```yaml").waitForExistence(timeout: timeout), "The code block is a new entry")
        XCTAssertTrue(text(of: row(containing: "```yaml")).contains("YAML"),
                      "Its badge names the block's own language: \(text(of: row(containing: "```yaml")))")
        screenshot(panel, "52-paste-special-result-in-history")

        // Paste Special on that code block again: another language replaces the tag instead of wrapping it again.
        send("pasteSpecial")
        XCTAssertTrue(special.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.language")).contains("YAML") }, "It keeps its language")
        element("pasteSpecial.language").click()
        special.typeText("c#")
        special.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.language")).contains("C#") })
        screenshot(special, "53-paste-special-code-block-language-replaced")
        element("pasteSpecial.copy").click()
        XCTAssertTrue(waitUntil { !special.exists })
        let replaced = "```csharp\ntargets:\n  $default:\n    builders:\n      enabled: true\n```"
        XCTAssertTrue(waitUntil { self.clipboard.string(forType: .string) == replaced },
                      "One block, tagged C#: \(clipboard.string(forType: .string) ?? "nothing")")
    }

    func test20dPasteSpecialOpensForTheSelectedEntry() {
        launch(open: "panel:image")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        // A pointer action first: an app-wide key press before any sets off an assertion inside XCTest.
        let pointer = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        pointer.hover()
        let point = pointer.screenPoint
        app.typeKey(.return, modifierFlags: .option)

        let special = element("pasteSpecialPanel")
        XCTAssertTrue(special.waitForExistence(timeout: timeout), "⌥↩ opens Paste Special for the selected image")
        XCTAssertEqual(special.frame.minX, point.x, accuracy: 2, "Opens at the pointer")
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.summary")).contains("1440×900") },
                      "It's the selected sample image, not the latest copy")
        screenshot(special, "42-paste-special-selected-entry")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !special.exists }, "esc closes it")
    }

    func test20eSeveralSelectedImagesAreConvertedTogether() throws {
        launch()
        let png = try Data(contentsOf: samplePNG())
        copyInApp { $0.setData(png, forType: .png) }
        send("panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        // Only images: the sample chart and the one just copied.
        element("panel.filter").click()
        app.menuItems["Image"].click()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'row'"))
        XCTAssertTrue(waitUntil { rows.count == 2 })
        rows.element(boundBy: 0).click()
        XCUIElement.perform(withKeyModifiers: .command) { rows.element(boundBy: 1).click() }
        XCTAssertTrue(waitUntil { self.element("panel.primary").label.contains("2 Entries") })
        app.typeKey(.return, modifierFlags: .option)

        let special = element("pasteSpecialPanel")
        XCTAssertTrue(special.waitForExistence(timeout: timeout), "⌥↩ opens Paste Special for both")
        pick("PNG", in: special)
        XCTAssertTrue(waitUntil { self.text(of: self.element("pasteSpecial.summary")).contains("2 images") }, "The preview totals both")
        screenshot(special, "43-paste-special-two-images")
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitUntil { self.copiedFiles().count == 2 }, "Both converted files are on the clipboard")
        XCTAssertEqual(Set(copiedFiles().map(\.lastPathComponent)), ["Image.png", "Image 2.png"])
    }

    func test21PasteSpecialShortcutsCanBeChanged() {
        launch(open: "settings")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        openSettingsPage("shortcuts", in: settings)
        let latest = settings.buttons["settings.shortcut.pasteSpecialLatest"]
        let selected = settings.buttons["settings.shortcut.pasteSpecial"]
        reveal(selected, in: settings)
        XCTAssertEqual(text(of: latest), "⌃⌘V", "Paste Special of the latest copy defaults to ⌃⌘V")
        XCTAssertEqual(text(of: selected), "⌥↩", "Paste Special of the selected entry defaults to ⌥↩")
        latest.click()
        settings.typeKey("v", modifierFlags: [.command, .option])
        XCTAssertTrue(waitUntil { self.text(of: latest) == "⌥⌘V" }, "Recorded ⌥⌘V")
        screenshot(settings, "39-settings-paste-special-shortcuts")
    }

    // MARK: Helpers

    private func openSettingsPage(_ page: String, in settings: XCUIElement) {
        let item = settings.descendants(matching: .any)["settings.nav.\(page)"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        item.click()
        XCTAssertTrue(element("settings.page.\(page)").waitForExistence(timeout: timeout))
    }

    private var panel: XCUIElement { app.dialogs["clipboardPanel"] }

    /// The list entry whose text contains this.
    private func row(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'row' AND (label CONTAINS %@ OR value CONTAINS %@)", text, text))
            .firstMatch
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func launch(open: String? = nil, extra: [String] = [], keepDefaults: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-e2e", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + (open.map { ["-e2eOpen", $0] } ?? []) + (keepDefaults ? ["-e2eKeepDefaults"] : []) + extra
        app.launch()
    }

    /// Sends a command to the running app (see `E2EFixtures`), without bringing it to the front.
    private func send(_ command: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.lazycatlabs.recopy.e2e"), object: command, userInfo: nil, deliverImmediately: true)
    }

    /// Drags the window by its bottom bar.
    private func drag(by offset: CGVector) {
        let handle = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        handle.click(forDuration: 0.2, thenDragTo: handle.withOffset(offset))
    }

    /// The visible area of the screen holding `frame`, in the same top-left coordinates XCUITest uses.
    private func visibleFrame(containing frame: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first?.frame else { return nil }
        return NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            return CGRect(x: visible.minX, y: primary.maxY - visible.maxY, width: visible.width, height: visible.height)
        }
        .first { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
    }

    /// Scrolls the window's list in small steps until the element is inside it. Big steps get accelerated by macOS
    /// and overshoot.
    private func reveal(_ element: XCUIElement, in window: XCUIElement) {
        // The page, not the sidebar.
        let list = window.scrollViews.matching(NSPredicate(format: "identifier BEGINSWITH 'settings.page.'")).firstMatch
        let visible = list.frame.insetBy(dx: 0, dy: 40)
        for _ in 0..<80 where !visible.contains(element.frame) {
            list.scroll(byDeltaX: 0, deltaY: element.frame.midY > visible.midY ? -8 : 8)
        }
        XCTAssertTrue(window.frame.contains(element.frame), "Scrolled into view")
    }

    /// The app's private clipboard in E2E runs.
    private var clipboard: NSPasteboard { NSPasteboard(name: NSPasteboard.Name("com.lazycatlabs.recopy.e2e")) }

    private func copiedFiles() -> [URL] {
        clipboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Copies something as another app would, then waits for ReCopy to record it (it checks every half second).
    private func copyInApp(_ write: (NSPasteboard) -> Void) {
        clipboard.clearContents()
        write(clipboard)
        RunLoop.current.run(until: .now.addingTimeInterval(1.5))
    }

    /// Opens the clipboard window, rests the pointer on it and closes it again, so Paste Special has a known pointer
    /// position. Also a pointer action before any app-wide key press, which otherwise trips an assertion in XCTest.
    private func parkPointer() -> CGPoint {
        launch(open: "panel")
        XCTAssertTrue(element("panel.search").waitForExistence(timeout: timeout))
        let pointer = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        pointer.hover()
        let point = pointer.screenPoint
        send("hide")
        XCTAssertTrue(waitUntil { !self.element("panel.search").exists })
        return point
    }

    /// An 800 × 500 PNG file named Sample.png.
    private func samplePNG() throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 500, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 500).fill()
        NSColor.systemIndigo.setFill()
        NSBezierPath(ovalIn: NSRect(x: 250, y: 100, width: 300, height: 300)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Sample.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// Clicks one of Paste Special's choices until it's selected: a click right as the window appears can be lost.
    private func pick(_ title: String, in special: XCUIElement) {
        let button = special.radioButtons[title]
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        // Segments report their state as a value of 1 or 0, not as isSelected.
        let isPicked = { (button.value as? NSNumber)?.boolValue == true || button.isSelected }
        XCTAssertTrue(waitUntil {
            if isPicked() { return true }
            button.click()
            return isPicked()
        }, "Picked \(title) (value: \(String(describing: button.value)))")
    }

    /// A button's or text's visible text, whichever XCUITest fills in.
    private func text(of element: XCUIElement) -> String {
        [element.title, element.label, element.value as? String ?? ""].first { !$0.isEmpty } ?? ""
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        }
        return condition()
    }

    /// The screen around the clipboard window only (menus and guides reach past it), so nothing else the user
    /// has open ends up in the report.
    private func screenshotAroundPanel(_ name: String) {
        let shot = XCUIScreen.main.screenshot().image
        let frame = panel.frame.insetBy(dx: -120, dy: -120)
        guard let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let primary = NSScreen.screens.first?.frame else { return screenshot(panel, name) }
        let scale = CGFloat(cg.width) / primary.width
        let crop = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let cropped = cg.cropping(to: crop) else { return screenshot(panel, name) }
        let attachment = XCTAttachment(image: NSImage(cgImage: cropped, size: .zero))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Kept in the test report; scripts/e2e.sh copies it to e2e-output/screenshots/<name>.png.
    private func screenshot(_ source: XCUIScreenshotProviding, _ name: String) {
        let attachment = XCTAttachment(screenshot: source.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
