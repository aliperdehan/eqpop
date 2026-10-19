import Cocoa

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The preview. A drag from it carries the result as PDF, PNG and a file, so it can be dropped into Keynote, Word, Finder…
final class PreviewView: NSImageView, NSDraggingSource {
    var dragItem: (() -> NSPasteboardItem?)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func mouseDragged(with event: NSEvent) {
        guard let item = dragItem?(), let img = image else { return }
        let di = NSDraggingItem(pasteboardWriter: item)
        di.setDraggingFrame(bounds, contents: img)
        beginDraggingSession(with: [di], event: event, source: self)
    }
}

final class App: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var panel: Panel!
    var input: NSTextView!
    let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let enginePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let status = NSTextField(wrappingLabelWithString: "")
    let preview = PreviewView()
    let renderer = Renderer()
    var preambleView: NSTextView!
    var preambleScroll: NSScrollView!
    var preambleHeight: NSLayoutConstraint!
    var preambleGap: NSLayoutConstraint!
    var inputEditing: TeXEditing!
    var preambleEditing: TeXEditing!
    var preambleShown = defaults.bool(forKey: "preambleShown")
    static let preamblePaneHeight: CGFloat = 130
    let hotkey = HotKey()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var shortcut = Shortcut.load()
    var lastPDF: Data?
    var lastKey: String?   // what lastPDF was rendered from; nil after a failed render
    var wantCopy = false
    var debounce: Timer?
    var hideAfterCopy = defaults.object(forKey: "hideAfterCopy") as? Bool ?? true

    static func plainCode(_ t: NSTextView) {
        t.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        t.isAutomaticQuoteSubstitutionEnabled = false
        t.isAutomaticDashSubstitutionEnabled = false
        t.isAutomaticTextReplacementEnabled = false
        t.isAutomaticSpellingCorrectionEnabled = false
        t.isContinuousSpellCheckingEnabled = false
        t.isAutomaticLinkDetectionEnabled = false
        t.isRichText = false
        t.allowsUndo = true
        t.textContainerInset = NSSize(width: 4, height: 6)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = Store.preamble()   // creates the preamble file on the first launch only
        buildMainMenu()
        buildPanel()
        buildStatusItem()
        HotKey.action = { [weak self] in self?.toggle() }
        if !hotkey.register(shortcut) {
            warn("\(shortcut.label) could not be registered (taken by another app, or refused by macOS). Choose another in the menu bar menu, for example ⌃⌥T.")
        }
        if CommandLine.arguments.contains("--show") { show() }   // for testing without pressing the hotkey
    }

    // MARK: window

    func buildPanel() {
        let scroll = NSTextView.scrollableTextView()
        input = scroll.documentView as? NSTextView
        App.plainCode(input)
        input.delegate = self
        input.string = defaults.string(forKey: "source") ?? "\\ce{2H2 + O2 -> 2H2O}"
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        inputEditing = TeXEditing(input)

        preambleScroll = NSTextView.scrollableTextView()
        preambleView = preambleScroll.documentView as? NSTextView
        App.plainCode(preambleView)
        preambleView.delegate = self
        preambleView.string = Store.preamble()
        preambleScroll.hasVerticalScroller = true
        preambleScroll.borderType = .bezelBorder
        preambleEditing = TeXEditing(preambleView)

        for m in Mode.allCases { modePopup.addItem(withTitle: m.title); modePopup.lastItem?.representedObject = m.rawValue }
        if let saved = defaults.string(forKey: "mode"), let m = Mode(rawValue: saved), let i = Mode.allCases.firstIndex(of: m) { modePopup.selectItem(at: i) }
        modePopup.target = self; modePopup.action = #selector(optionsChanged)

        enginePopup.autoenablesItems = false
        for e in Engine.allCases {
            enginePopup.addItem(withTitle: e.rawValue)
            enginePopup.lastItem?.isEnabled = Toolchain.find(e.rawValue) != nil
        }
        let savedEngine = Engine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .pdflatex
        enginePopup.selectItem(withTitle: savedEngine.rawValue)
        enginePopup.target = self; enginePopup.action = #selector(optionsChanged)

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 4
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.imageAlignment = .alignCenter
        preview.isEditable = false
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.white.cgColor   // black text stays readable in dark mode
        preview.layer?.cornerRadius = 6
        preview.setContentHuggingPriority(.defaultLow, for: .vertical)
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        preview.dragItem = { [weak self] in self?.pasteboardItem() }

        let edit = NSButton(title: "Preamble", target: self, action: #selector(togglePreamble))
        let save = NSButton(title: "Save…", target: self, action: #selector(saveAs))
        let copy = NSButton(title: "Copy  ⌘↩", target: self, action: #selector(copyRendered))
        copy.bezelStyle = .rounded
        // plain constraints, and every row but the preview has a fixed height: the preview takes all the extra room
        let content = NSView()
        let m: CGFloat = 12
        for v in [preambleScroll!, scroll, modePopup, enginePopup, preview, status, edit, save, copy] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            preambleScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            preambleScroll.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            preambleScroll.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            modePopup.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            modePopup.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            enginePopup.leadingAnchor.constraint(equalTo: modePopup.trailingAnchor, constant: 8),
            enginePopup.centerYAnchor.constraint(equalTo: modePopup.centerYAnchor),
            preview.topAnchor.constraint(equalTo: modePopup.bottomAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            status.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            edit.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8),
            edit.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            save.leadingAnchor.constraint(equalTo: edit.trailingAnchor, constant: 8),
            save.centerYAnchor.constraint(equalTo: edit.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            copy.centerYAnchor.constraint(equalTo: edit.centerYAnchor),
            edit.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
        ])

        preambleHeight = preambleScroll.heightAnchor.constraint(equalToConstant: preambleShown ? App.preamblePaneHeight : 0)
        preambleGap = scroll.topAnchor.constraint(equalTo: preambleScroll.bottomAnchor, constant: preambleShown ? 8 : 0)
        NSLayoutConstraint.activate([preambleHeight, preambleGap])
        preambleScroll.isHidden = !preambleShown

        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520 + (preambleShown ? App.preamblePaneHeight + 8 : 0)),
                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "eqpop"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.setFrameAutosaveName("eqpopPanel")
        if !panel.setFrameUsingName("eqpopPanel") { panel.center() }
    }

    func buildMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Hide eqpop", action: #selector(hide), keyEquivalent: "w").target = self
        let c = appMenu.addItem(withTitle: "Copy rendered result", action: #selector(copyRendered), keyEquivalent: "\r")
        c.keyEquivalentModifierMask = .command
        c.target = self
        appMenu.addItem(withTitle: "Save as…", action: #selector(saveAs), keyEquivalent: "s").target = self
        let editItem = NSMenuItem(); bar.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = bar
    }

    func buildStatusItem() {
        item.button?.image = NSImage(systemSymbolName: "function", accessibilityDescription: "eqpop")
        rebuildMenu()
    }

    func rebuildMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Show eqpop  (\(shortcut.label))", action: #selector(show), keyEquivalent: "").target = self
        m.addItem(withTitle: "Edit preamble", action: #selector(editPreamble), keyEquivalent: "").target = self
        m.addItem(withTitle: "Show preamble file in Finder", action: #selector(revealPreamble), keyEquivalent: "").target = self
        let h = m.addItem(withTitle: "Hide after copying", action: #selector(toggleHideAfterCopy), keyEquivalent: "")
        h.target = self
        h.state = hideAfterCopy ? .on : .off
        m.addItem(withTitle: "Change shortcut (\(shortcut.label))…", action: #selector(changeShortcut), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit eqpop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
    }

    // MARK: show / hide

    func toggle() { panel.isVisible && NSApp.isActive ? hide() : show() }

    @objc func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(input)
        input.selectAll(nil)
        if lastPDF == nil { schedule(after: 0) }
    }

    /// Hiding the whole app (not just the panel) gives the focus back to the app the user came from.
    @objc func hide() {
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    func textViewDidChangeSelection(_ n: Notification) {
        guard let tv = n.object as? NSTextView else { return }
        (tv === preambleView ? preambleEditing : inputEditing)?.updateBrackets()
    }

    func textView(_ t: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { hide(); return true }
        return false
    }

    // MARK: rendering

    func textDidChange(_ n: Notification) {
        if (n.object as? NSTextView) === preambleView {
            try? preambleView.string.write(to: Store.preambleURL, atomically: true, encoding: .utf8)   // the file is the preamble
            schedule(after: 0.6)
        } else {
            defaults.set(input.string, forKey: "source")
            schedule(after: 0.4)
        }
    }

    @objc func optionsChanged() {
        defaults.set(selectedMode.rawValue, forKey: "mode")
        defaults.set(selectedEngine.rawValue, forKey: "engine")
        schedule(after: 0)
    }

    var selectedMode: Mode { Mode(rawValue: modePopup.selectedItem?.representedObject as? String ?? "") ?? .display }
    var selectedEngine: Engine { Engine(rawValue: enginePopup.titleOfSelectedItem ?? "") ?? .pdflatex }

    func schedule(after delay: TimeInterval) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.renderNow() }
    }

    func renderNow() {
        let src = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.isEmpty { renderer.cancel(); lastPDF = nil; preview.image = nil; setStatus("", error: false); return }
        setStatus("rendering…", error: false)
        let started = Date()
        let req = RenderRequest(source: src, mode: selectedMode, engine: selectedEngine, preamble: Store.preamble())
        let key = App.key(req)
        renderer.render(req) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let pdf):
                self.lastPDF = pdf
                self.lastKey = key
                self.preview.image = NSImage(data: pdf)
                let size = PDFTools.pointSize(pdf).map { String(format: "%.0f × %.0f pt", $0.width, $0.height) } ?? ""
                self.setStatus(String(format: "%@ · %.2f s", size, Date().timeIntervalSince(started)), error: false)
                if self.wantCopy { self.wantCopy = false; self.finishCopy(pdf) }
            case .failure(.cancelled):
                break
            case .failure(.noEngine(let name)):
                self.failed()
                self.setStatus("\(name) not found. Install TeX (MacTeX or BasicTeX) or pick another engine.", error: true)
            case .failure(.failed(let why)):
                self.failed()
                self.setStatus(why, error: true)
            }
        }
    }

    /// A failed render: what is on screen is no longer the current text, and a pending copy must not take it instead.
    func failed() {
        lastKey = nil
        if wantCopy { wantCopy = false; NSSound.beep() }
    }

    static func key(_ r: RenderRequest) -> String { "\(r.mode.rawValue)|\(r.engine.rawValue)|\(r.preamble)|\(r.source)" }

    func setStatus(_ s: String, error: Bool) {
        status.stringValue = s
        status.textColor = error ? .systemRed : .secondaryLabelColor
        status.toolTip = error ? s : nil
    }

    // MARK: copy and drag

    @objc func copyRendered() {
        // copy only a result made from exactly what is in the window now; otherwise render again and copy that
        let src = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = App.key(RenderRequest(source: src, mode: selectedMode, engine: selectedEngine, preamble: Store.preamble()))
        if let pdf = lastPDF, lastKey == now { finishCopy(pdf) }
        else { wantCopy = true; schedule(after: 0) }
    }

    func finishCopy(_ pdf: Data) {
        PDFTools.copyToClipboard(pdf)
        setStatus("copied (PDF + PNG)", error: false)
        if hideAfterCopy { hide() }
    }

    func pasteboardItem() -> NSPasteboardItem? {
        guard let pdf = lastPDF else { return nil }
        let file = Store.cacheDir.appendingPathComponent("equation.pdf")
        guard (try? pdf.write(to: file)) != nil else { return nil }
        let pbi = NSPasteboardItem()
        pbi.setData(pdf, forType: .pdf)
        if let png = PDFTools.png(from: pdf) { pbi.setData(png, forType: .png) }
        pbi.setString(file.absoluteString, forType: .fileURL)
        return pbi
    }

    // MARK: menu actions

    @objc func togglePreamble() { setPreamblePane(shown: !preambleShown) }

    @objc func editPreamble() {
        show()
        setPreamblePane(shown: true)
        panel.makeFirstResponder(preambleView)
    }

    /// Shows or hides the preamble pane; the window grows and shrinks by the pane's height, so the rest keeps its size.
    func setPreamblePane(shown: Bool) {
        guard shown != preambleShown else { return }
        preambleShown = shown
        defaults.set(shown, forKey: "preambleShown")
        if shown { preambleView.string = Store.preamble() }   // an edit made in another editor is picked up
        let delta = App.preamblePaneHeight + 8
        var f = panel.frame
        f.size.height += shown ? delta : -delta
        f.origin.y -= shown ? delta : -delta   // the top edge stays where it is
        preambleScroll.isHidden = !shown
        preambleHeight.constant = shown ? App.preamblePaneHeight : 0
        preambleGap.constant = shown ? 8 : 0
        panel.setFrame(f, display: true, animate: false)
        if !shown { panel.makeFirstResponder(input) }
    }

    @objc func saveAs() {
        guard let pdf = lastPDF else { NSSound.beep(); return }
        let formats = ["pdf", "png", "svg"]
        let chooser = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 26), pullsDown: false)
        chooser.addItems(withTitles: ["PDF", "PNG", "SVG"])
        let sp = NSSavePanel()
        sp.nameFieldStringValue = "equation.pdf"
        sp.accessoryView = chooser
        sp.isExtensionHidden = false
        let change = ChooserAction { [weak sp, weak chooser] in
            guard let sp = sp, let c = chooser else { return }
            sp.nameFieldStringValue = ((sp.nameFieldStringValue as NSString).deletingPathExtension as NSString).appendingPathExtension(formats[c.indexOfSelectedItem]) ?? ""
        }
        chooser.target = change
        chooser.action = #selector(ChooserAction.go)
        panel.level = .normal   // the save dialog must not hide behind the floating panel
        NSApp.activate(ignoringOtherApps: true)
        let answer = sp.runModal()
        panel.level = .floating
        guard answer == .OK, let url = sp.url else { return }
        let data: Data?
        switch url.pathExtension.lowercased() {
        case "png": data = PDFTools.png(from: pdf)
        case "svg":
            data = PDFTools.svg(from: pdf)
            if data == nil { warn("SVG needs pdftocairo (brew install poppler) or mutool (brew install mupdf-tools).") }
        default: data = pdf
        }
        if let d = data { do { try d.write(to: url); setStatus("saved \(url.lastPathComponent)", error: false) } catch { warn(error.localizedDescription) } }
    }
    @objc func revealPreamble() { _ = Store.preamble(); NSWorkspace.shared.activateFileViewerSelecting([Store.preambleURL]) }

    @objc func toggleHideAfterCopy() {
        hideAfterCopy.toggle()
        defaults.set(hideAfterCopy, forKey: "hideAfterCopy")
        rebuildMenu()
    }

    @objc func changeShortcut() {
        let catcher = ShortcutCatcher(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
        catcher.field.stringValue = shortcut.label
        let a = NSAlert()
        a.messageText = "Press the new shortcut"
        a.informativeText = "Use Control, Option or Command with a key."
        a.accessoryView = catcher
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        a.window.initialFirstResponder = catcher
        DispatchQueue.main.async { a.window.makeFirstResponder(catcher) }
        guard a.runModal() == .alertFirstButtonReturn, let s = catcher.captured else { return }
        let old = shortcut
        if hotkey.register(s) { shortcut = s; s.save() }
        else { _ = hotkey.register(old); warn("\(s.label) is taken by another app.") }
        rebuildMenu()
    }

    func warn(_ text: String) {
        let a = NSAlert()
        a.messageText = "eqpop"
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

/// Lets a closure be the target of a control.
final class ChooserAction: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func go() { body() }
}
