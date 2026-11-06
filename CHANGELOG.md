# Changelog

What changed in each version of ReCopy (called Copaste before). The newest version is first. Each version's section is also the text for
its GitHub release (tag `vX.Y.Z`).

## 0.11.2 — 2026-11-06

### Changed

- ReCopy is now signed with a Developer ID and notarized by Apple, so macOS opens it without the "can't be
  verified" warning. The signature changed again: grant Accessibility once more after updating (for pasting into
  other apps). <!-- github-only -->

## 0.11.1 — 2026-11-04

### New

- **ReCopy is coming to the Mac App Store** as ReCopy — Clipboard Manager. The download from GitHub and Homebrew
  stays the same, with the same features. <!-- github-only -->

### Changed

- Your vault keeps its settings in a `.recopy` folder (it was `.copaste`). An existing vault's settings are copied
  over the first time it opens, and the old folder stays, so a Mac still on an older version keeps working.
- Feedback and bug reports now go to help.me@lazycatlabs.com.
- ReCopy is now signed with the Lazycat Labs team certificate, so macOS sees a new signature: grant Accessibility
  again after updating (for pasting into other apps). <!-- github-only -->

### Fixed

- If ReCopy can't open your history folder, for example on a drive that isn't connected, it asks for the folder
  again instead of showing an empty history.

## 0.10.0 — 2026-11-04

### New

- **Crop and rotate images** in the annotation editor. Pick **Crop** and drag over the part to keep, or click
  **Rotate Right** to turn the image a quarter. Your marks so far are kept in the image, and Undo brings back the
  earlier version.
- **Sponsor ReCopy** from Settings › About: GitHub Sponsors, Buy Me a Coffee, Ko-fi, PayPal and Saweria (for
  supporters in Indonesia). Settings search finds them by name.

### Changed

- Under the hood: the project is updated for Xcode 27.2. Nothing looks or works differently.

## 0.9.2 — 2026-11-02

### Changed

- **Copaste is now ReCopy.** Same app, new name. Your vault opens as before, and your shortcuts, text size and window
  position are copied over on first launch.
- Homebrew: the cask is now `recopy` (`brew install --cask lazycatlabs/tap/recopy`). `brew upgrade` moves you over
  from `copaste`.
- macOS sees ReCopy as a new app, so grant Accessibility again (for pasting into other apps). You can remove the old
  Copaste app afterwards.

## 0.9.1 — 2026-11-01

### Changed

- Under the hood: the code block language list in Paste Special is cleaned up for Swift 6. Nothing looks or works
  differently.

## 0.9.0 — 2026-11-01

### New

- **Paste Special for text**: the same shortcuts as for images (⌥↩ on the selected entry, ⌃⌘V for the latest copy)
  open text options when the entry is text.
  - **Reformat**: As Is, Tidy (shared indentation, trailing spaces and extra blank lines removed), and for JSON:
    Indented or One Line.
  - **Paste As**: Plain Text, Code Block (Markdown fence), or Monospaced (for Notes, Mail, Pages and web editors).
  - **Code Block Language**: search about forty languages by name, tag or alias, or type a tag of your own. On text
    that's already a code block, the new language replaces the old tag.
  - The result is saved to the history as its own entry.
- **Code detection**: JSON, HTML, XML and 15 languages (Swift, Dart, Kotlin, Java, Python, JavaScript, Go, Rust,
  C/C++, SQL, CSS, Shell…). A Markdown code block is named by its own tag.
- **Code filter and badges**: the type filter has **Code**, and code entries show their language.

### Changed

- Selecting several entries of different kinds, or several texts, shows a message instead of Paste Special. Several
  images still convert together.

### Fixed

- A copy made just before opening Copaste or Paste Special is now always the latest entry.

## 0.8.2 — 2026-10-31

### Changed

- Under the hood: the windows and Settings panes are reorganized into smaller pieces, following the same layout as
  Masa. Nothing looks or works differently.

## 0.8.1 — 2026-10-31

### New

- **Paste Special from anywhere**: copy an image (or an image file in Finder) and press ⌃⌘V in any app. Paste
  Special opens at the pointer for that copy, without opening the clipboard window. If the last copy isn't an image,
  a message says so.
- **Several images at once**: in the clipboard window, pick images with ⌘-click or ⇧-click and press ⌥↩. They're
  converted with the same options and pasted together with one ⌘V.
- **Paste** is always offered in Paste Special.
- **Shortcuts in groups**: Settings › Shortcuts lists them under In Any App, Clipboard Window and Selected Entry.

### Fixed

- The selected page's icon in the Settings sidebar was hidden by the selection color.
- Paste Special showed "Converting…" forever when an image couldn't be read; it now says so.

## 0.8.0 — 2026-10-31

### New

- **Paste Special**: select an image (or an image file copied in Finder) and press ⌥↩ to convert it before
  pasting. Choose PNG, JPEG, HEIC, TIFF, SVG or PDF, shrink it to 75%, 50% or 25%, and set the quality for JPEG and
  HEIC. A preview shows the new file size before you paste. The image is pasted as a file, so apps get the format
  you picked. The options open right at the pointer.
- The Paste Special shortcut can be changed in Settings › Shortcuts.

## 0.7.0 — 2026-10-30

### New

- **Move and resize marks in Annotate**: pick the new Select tool (the pointer), click a mark, then drag it to move
  it or drag a corner handle to resize it. Text grows or shrinks with its corner.
- **Undo goes further**: it now also reverses moves, resizes and Clear.

## 0.6.0 — 2026-10-30

### New

- **More ways to mark up images in Annotate**: Circle and Triangle sit next to Rectangle, and any shape can be drawn as
  a border or filled with the color.
- **Mosaic blur**: drag over part of an image to pixelate it, for passwords, names or anything you'd rather not share.
  The hidden content can't be recovered from the saved image.
- **Size slider**: the stroke size is now a slider, with a dot beside it that shows how wide the line will be. It also
  sets the text size and the mosaic's square size.
- **Sponsor Copaste**: Settings › About links to GitHub Sponsors.

### Fixed

- The three stroke-size buttons in Annotate all looked the same size.

## 0.5.2 — 2026-10-28

### New

- **Copaste is now open source under the GNU GPL v3.** Settings › About shows the license, links to the source code on
  GitHub and carries the copyright and no-warranty notice. You're free to use, share and change Copaste under the
  license's terms.

## 0.5.1 — 2026-10-27

### Improved

- **Uses less memory and CPU**: image thumbnails and previews are loaded at the size they're shown instead of at full
  size, and the memory they take is capped. Opening the clipboard window only reads entries that changed since last
  time, instead of the whole history. Screenshots and other PNG images are saved as copied, without converting them
  first, and the clipboard check lets macOS group it with other work so it wakes your Mac less.

## 0.5.0 — 2026-10-26

### New

- **Welcome tour**: the first time you open Copaste, a short interactive introduction shows what it does before you
  choose the folder for your history. Try the global shortcut and watch its keys light up, see how the folder syncs
  between your Macs, and hover over Search, Pin, Groups, Annotate and Notes. Move with Back/Next, the page dots or
  ← →, or skip straight to choosing the folder. It's shown once per Mac.

### Fixed

- Copaste builds with Xcode 26.6 again (Swift 6.3 rejected a name in the clipboard window's group filter).

## 0.4.1 — 2026-10-26

### Fixed

- Copying several images at once and pasting with ⌘V now pastes all of them, not only the first. Each image goes on
  the clipboard as its file, the same as several images copied in Finder.

## 0.4.0 — 2026-10-26

### New

- **Paste several entries at once**: in the clipboard window, ⌘-click to pick entries, ⇧-click or ⇧↑↓ to pick a
  range. ↩ pastes them all in list order; ⌘↩ copies them. Text entries are joined one per line into a single paste;
  with images or files among them, each entry is pasted in turn. esc clears the selection.
- **Notes**: add your own note to any entry with the “Add a note…” field above its preview. Notes are saved as you
  type and included in search; when a search matches a note, the entry shows it under its title with the match
  highlighted. Entries with a note show a note icon.

## 0.3.0 — 2026-10-25

### New

- **Storage used**: Settings › History shows how much space Copaste's history takes on disk (entries, images and
  link previews) and how many entries it holds, with Show in Finder.
- **Delete Entries**: delete history in bulk by when entries were last copied (in the last hour, 24 hours, 7 days or
  month, or more than 7 days, a month, 3 months or a year ago), by type and by group. Pinned entries are kept unless
  you include them. Copaste shows how many entries match and how much space they take, and asks before deleting.

### Changed

- Delete Entries replaces Clear History. Its standard choices (any time, all types, pinned kept) do the same thing.

## 0.2.1 — 2026-10-25

### Fixed

- In dark mode the clipboard window was barely darker than in 0.1.1, so the wallpaper could still show through
  behind the text. Its background is now darker and easier to read on any wallpaper.

## 0.2.0 — 2026-10-25

### New

- **Groups**: put entries in groups and filter the history by group. Create, rename and delete groups in Settings ›
  Groups; add an entry to a group from its right-click menu or Actions (⌘K); pick a group with the folder filter at
  the top of the clipboard window. Entries show their group as a tag. Deleting a group keeps its entries.
- **Move the clipboard window**: drag it by its top or bottom bar. Guides show the centre of the screen and the window
  snaps to it. Copaste remembers where you put it; Settings › Appearance › Center puts it back.
- **⌘1…⌘9 hints**: hold ⌘ in the clipboard window to see which entry each number pastes.
- **Change every shortcut**: Settings › Shortcuts lists all of them. Paste, copy, Actions, open, annotate, save, pin
  and delete can be re-recorded and reset, as well as the shortcut that opens Copaste.
- **Text in Annotate**: the new Text tool places a text box where you click. **Copy to Clipboard** (⌘C) puts the
  edited image on the clipboard without saving it as a new entry.
- **New Settings**: a sidebar with pages and a search field. Type a setting's name to jump to its page.
- **Updates and changelog**: Settings › Updates shows whether a newer Copaste is out, with a Download button, and
  what changed in each version.

### Changed

- New look for the clipboard window: clearer text colours, key caps for each key (⌘ K), a darker background in dark
  mode, and "Search your clipboard" in the search field. The date filter now reads "Any Day".
- Text uses the same sizes as other Mac apps by default and follows macOS's text size. Settings › Appearance ›
  Text size still offers Small, Large and Extra Large.
- "Paste into the app in front" is now "Paste after choosing an entry", with a note on what it does when on or off.

### Fixed

- After choosing an entry, the app you were in didn't always get the keyboard back, so pasting needed a click on its
  window first. Copaste now hands the focus back and waits for that app before pasting.
- Settings and the annotation editor sometimes opened without the keyboard. They now come to the front, ready to type.
- After "Save as New Entry" in Annotate, the clipboard window now opens again with the new entry selected.

## 0.1.1 — 2026-10-25

### New

- **Universal Clipboard**: items copied on your iPhone, iPad or another Mac are saved as soon as they arrive, marked
  "Universal Clipboard". Large items such as photos download in the background. Turn it off in Settings › History ›
  Save Universal Clipboard items immediately.

### Fixed

- Settings (and the annotation and welcome windows) sometimes opened behind other apps, on another Space or on
  another screen. They now come to the front, in the middle of the screen you're on.

## 0.1.0 — 2026-10-25

The first release: a clipboard history for macOS, in the menu bar.

### Clipboard history

- Press **⇧⌘V** in any app to open the floating clipboard window. Change the shortcut in Settings.
- Text, links, e-mail addresses, colours, images and files are recognised, each with its own icon: favicons for
  links, thumbnails for images, swatches for colours.
- Filter by type or by the day an entry was first copied, and search everything, including text in images.
- Entries are grouped under Pinned, Today, Yesterday, This Week, This Month and then by month.
- Details show the source app, type, characters and words, image size, times copied and pasted, and when first and
  last.
- Double-click copies and closes the window, ↩ pastes into the app you were in, ⌘1…⌘9 paste one of the first nine
  entries and ⌘K shows every action for the selected entry.

### Actions

- Open links, write e-mails, copy a colour as HEX, RGB or HSL, save images and text to files, show files in Finder.
- Annotate images with a pen, highlighter, rectangle and arrow; the result is saved as a new entry and copied.

### Your history, your folder

- Choose the folder your history is kept in: a folder in iCloud Drive, Google Drive or OneDrive shares it between
  your Macs.
- Keep history from a day to forever; pinned entries are never cleaned up.
- Passwords marked as secret are never recorded, and whole apps can be ignored.
- Import the images and rich-text copies Raycast keeps.

### Settings

- Text size, copy and paste sounds, toasts after copying and pasting, open at login.
- Send feedback or report a bug from the menu bar or Settings › About.
