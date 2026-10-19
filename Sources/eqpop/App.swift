import Cocoa
import ServiceManagement

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
    var preambleScroll: NSScrollView!   // the scroll view holding the pane's text view
    var paneBox: NSView!                // the pane: its tab control and the scroll view
    var paneSeg: NSSegmentedControl!    // 0 = LaTeX preamble, 1 = pdfmd metadata
    let pdfmdPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let errors = ErrorList()
    let logWindow = LogWindow()
    var lastLog = ""
    var logButton: NSButton!
    var preambleHeight: NSLayoutConstraint!
    var preambleGap: NSLayoutConstraint!
    var inputEditing: TeXEditing!
    var preambleEditing: TeXEditing!
    var preambleShown = defaults.bool(forKey: "preambleShown")
    static let preamblePaneHeight: CGFloat = 156
    let hotkey = HotKey()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var shortcut = Shortcut.load()
    var lastPDF: Data?
    var lastKey: String?   // what lastPDF was rendered from; nil after a failed render
    var wantCopy = false
    var debounce: Timer?
    var hideAfterCopy = defaults.object(forKey: "hideAfterCopy") as? Bool ?? true
    var live = defaults.object(forKey: "live") as? Bool ?? true   // render while typing; off = only on ⌘R or ⌘↩
    var liveBox: NSButton!
    var inputScroll: NSScrollView!
    var chain: [NSLayoutConstraint] = []   // the vertical order of the rows; changes with the preview position
    var content: NSView!
    var rows: [NSView] = []                // preview, status, the pane (and the editor under it), the option row, the buttons
    var lineNumbers = defaults.object(forKey: "lineNumbers") as? Bool ?? true
    var previewAbove = defaults.object(forKey: "previewAbove") as? Bool ?? true   // LaTeXiT's order: the result on top

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

    static var screenshotPath: String?
    static var screenshotAppearance: String?   // "light" or "dark"; unset: the system's

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = Store.preamble()   // creates the preamble file on the first launch only
        if let a = App.screenshotAppearance { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        buildMainMenu()
        buildPanel()
        if let out = App.screenshotPath { screenshot(to: out); return }
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
        inputScroll = scroll
        scroll.verticalRulerView = LineNumbers(scroll, input)
        scroll.hasVerticalRuler = true

        preambleScroll = NSTextView.scrollableTextView()
        preambleView = preambleScroll.documentView as? NSTextView
        App.plainCode(preambleView)
        preambleView.delegate = self
        preambleView.string = Store.preamble()
        preambleScroll.hasVerticalScroller = true
        preambleScroll.borderType = .bezelBorder
        preambleEditing = TeXEditing(preambleView)
        preambleScroll.verticalRulerView = LineNumbers(preambleScroll, preambleView)
        preambleScroll.hasVerticalRuler = true
        paneSeg = NSSegmentedControl(labels: ["Preamble", "pdfmd metadata"], trackingMode: .selectOne, target: self, action: #selector(paneChanged))
        paneSeg.controlSize = .small
        paneSeg.selectedSegment = 0
        paneBox = NSView()
        for v in [paneSeg!, preambleScroll!] { v.translatesAutoresizingMaskIntoConstraints = false; paneBox.addSubview(v) }
        NSLayoutConstraint.activate([
            paneSeg.topAnchor.constraint(equalTo: paneBox.topAnchor),
            paneSeg.leadingAnchor.constraint(equalTo: paneBox.leadingAnchor),
            preambleScroll.topAnchor.constraint(equalTo: paneSeg.bottomAnchor, constant: 4),
            preambleScroll.leadingAnchor.constraint(equalTo: paneBox.leadingAnchor),
            preambleScroll.trailingAnchor.constraint(equalTo: paneBox.trailingAnchor),
            preambleScroll.bottomAnchor.constraint(equalTo: paneBox.bottomAnchor),
        ])

        for m in Mode.allCases { modePopup.addItem(withTitle: m.title); modePopup.lastItem?.representedObject = m.rawValue }
        if let saved = defaults.string(forKey: "mode"), let m = Mode(rawValue: saved), let i = Mode.allCases.firstIndex(of: m) { modePopup.selectItem(at: i) }
        modePopup.target = self; modePopup.action = #selector(optionsChanged)

        enginePopup.autoenablesItems = false
        for e in Engine.allCases {
            enginePopup.addItem(withTitle: e.rawValue)
            enginePopup.lastItem?.isEnabled = e == .pdfmd ? Toolchain.pdfmdCommand() != nil : Toolchain.find(e.rawValue) != nil
        }
        let savedEngine = Engine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .pdflatex
        enginePopup.selectItem(withTitle: savedEngine.rawValue)
        enginePopup.target = self; enginePopup.action = #selector(optionsChanged)

        pdfmdPopup.addItems(withTitles: pdfmdEngines)
        pdfmdPopup.selectItem(withTitle: defaults.string(forKey: "pdfmdEngine") ?? "auto")
        pdfmdPopup.toolTip = "The PDF engine pdfmd uses (its -e). auto: pdfmd's own choice."
        pdfmdPopup.target = self; pdfmdPopup.action = #selector(optionsChanged)
        applyEngineChoice()

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
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor(white: 0.5, alpha: 0.35).cgColor   // keeps the white sheet visible on a light window
        preview.setContentHuggingPriority(.defaultLow, for: .vertical)
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        preview.dragItem = { [weak self] in self?.pasteboardItem() }
        errors.onJump = { [weak self] line in self?.jump(toLine: line) }
        errors.scroll.isHidden = true

        liveBox = NSButton(checkboxWithTitle: "Live", target: self, action: #selector(toggleLive))
        liveBox.state = live ? .on : .off
        liveBox.toolTip = "Render while typing. Off: render with ⌘R, or with ⌘↩ (which also copies)."
        let edit = NSButton(title: "Preamble", target: self, action: #selector(togglePreamble))
        let save = NSButton(title: "Save…", target: self, action: #selector(saveAs))
        logButton = NSButton(title: "Log", target: self, action: #selector(showLog))
        let copy = NSButton(title: "Copy  ⌘↩", target: self, action: #selector(copyRendered))
        copy.bezelStyle = .rounded
        // plain constraints, and every row but the preview has a fixed height: the preview takes all the extra room
        content = NSView()
        let m: CGFloat = 12
        for v in [paneBox!, scroll, modePopup, enginePopup, pdfmdPopup, liveBox!, preview, errors.scroll, status, edit, save, logButton!, copy] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            paneBox.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            paneBox.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            modePopup.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            enginePopup.leadingAnchor.constraint(equalTo: modePopup.trailingAnchor, constant: 8),
            enginePopup.centerYAnchor.constraint(equalTo: modePopup.centerYAnchor),
            pdfmdPopup.leadingAnchor.constraint(equalTo: enginePopup.trailingAnchor, constant: 8),
            pdfmdPopup.centerYAnchor.constraint(equalTo: modePopup.centerYAnchor),
            liveBox.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            liveBox.centerYAnchor.constraint(equalTo: modePopup.centerYAnchor),
            preview.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            errors.scroll.topAnchor.constraint(equalTo: preview.topAnchor),
            errors.scroll.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
            errors.scroll.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            errors.scroll.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            status.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            edit.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            save.leadingAnchor.constraint(equalTo: edit.trailingAnchor, constant: 8),
            save.centerYAnchor.constraint(equalTo: edit.centerYAnchor),
            logButton.leadingAnchor.constraint(equalTo: save.trailingAnchor, constant: 8),
            logButton.centerYAnchor.constraint(equalTo: edit.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            copy.centerYAnchor.constraint(equalTo: edit.centerYAnchor),
        ])

        preambleHeight = paneBox.heightAnchor.constraint(equalToConstant: preambleShown ? App.preamblePaneHeight : 0)
        preambleGap = scroll.topAnchor.constraint(equalTo: paneBox.bottomAnchor, constant: preambleShown ? 8 : 0)
        NSLayoutConstraint.activate([preambleHeight, preambleGap])
        paneBox.isHidden = !preambleShown
        rows = [preview, status, paneBox, modePopup, edit]   // the rows, see applyLayout
        applyLayout()
        scroll.rulersVisible = lineNumbers
        preambleScroll.rulersVisible = lineNumbers

        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520 + (preambleShown ? App.preamblePaneHeight + 8 : 0)),
                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "eqpop"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        if App.screenshotPath != nil { panel.center(); return }   // never touch the saved frame
        panel.setFrameAutosaveName("eqpopPanel")
        if !panel.setFrameUsingName("eqpopPanel") { panel.center() }
    }

    /// The rows run top to bottom in one chain: the preview and its status line, the pane with the editor, the options, the
    /// buttons. The preview goes first or comes right after the editor and the options, as the user chose.
    func applyLayout() {
        NSLayoutConstraint.deactivate(chain)
        let m: CGFloat = 12
        let (preview, status, pane, options, buttons) = (rows[0], rows[1], rows[2], rows[3], rows[4])
        let editor = inputScroll!
        // each row as (its top view, its bottom view)
        let order: [(NSView, NSView)] = previewAbove
            ? [(preview, preview), (status, status), (pane, editor), (options, options), (buttons, buttons)]
            : [(pane, editor), (options, options), (preview, preview), (status, status), (buttons, buttons)]
        var c = [order[0].0.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
                 order[order.count - 1].1.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m)]
        for i in 1..<order.count { c.append(order[i].0.topAnchor.constraint(equalTo: order[i - 1].1.bottomAnchor, constant: 8)) }
        chain = c
        NSLayoutConstraint.activate(chain)
    }

    @objc func togglePreviewAbove() {
        previewAbove.toggle()
        defaults.set(previewAbove, forKey: "previewAbove")
        applyLayout()
        content.needsLayout = true
    }

    @objc func toggleLineNumbers() {
        lineNumbers.toggle()
        defaults.set(lineNumbers, forKey: "lineNumbers")
        inputScroll.rulersVisible = lineNumbers
        preambleScroll.rulersVisible = lineNumbers
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(togglePreviewAbove) { item.state = previewAbove ? .on : .off }
        if item.action == #selector(toggleLineNumbers) { item.state = lineNumbers ? .on : .off }
        return true
    }

    func buildMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Hide eqpop", action: #selector(hide), keyEquivalent: "w").target = self
        let c = appMenu.addItem(withTitle: "Copy rendered result", action: #selector(copyRendered), keyEquivalent: "\r")
        c.keyEquivalentModifierMask = .command
        c.target = self
        appMenu.addItem(withTitle: "Render now", action: #selector(renderNowAction), keyEquivalent: "r").target = self
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
        let viewItem = NSMenuItem(); bar.addItem(viewItem)
        let view = NSMenu(title: "View"); viewItem.submenu = view
        view.addItem(withTitle: "Preview above the editor", action: #selector(togglePreviewAbove), keyEquivalent: "").target = self
        view.addItem(withTitle: "Line numbers", action: #selector(toggleLineNumbers), keyEquivalent: "").target = self
        NSApp.mainMenu = bar
    }

    func buildStatusItem() {
        item.button?.image = App.menuBarGlyph()
        rebuildMenu()
    }

    /// "f(x)" set in STIX (shipped with macOS, SIL OFL) as a template image, so the menu bar tints it; the app icon is
    /// drawn from the same font. Falls back to the system symbol if the font is missing.
    static func menuBarGlyph() -> NSImage? {
        guard let it = NSFont(name: "STIXGeneral-Italic", size: 15), let up = NSFont(name: "STIXGeneral-Regular", size: 15) else {
            return NSImage(systemSymbolName: "function", accessibilityDescription: "eqpop")
        }
        let s = NSMutableAttributedString()
        for (t, f) in [("f", it), ("(", up), ("x", it), (")", up)] {
            s.append(NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: NSColor.black]))
        }
        let line = CTLineCreateWithAttributedString(s)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)   // the outlines: the italic f hangs left of its origin
        let img = NSImage(size: NSSize(width: ceil(ink.width) + 4, height: 18), flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.textPosition = CGPoint(x: 2 - ink.minX, y: r.height / 2 - ink.midY)
            CTLineDraw(line, ctx)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "eqpop"
        return img
    }

    func rebuildMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Show eqpop  (\(shortcut.label))", action: #selector(show), keyEquivalent: "").target = self
        m.addItem(withTitle: "Edit preamble", action: #selector(editPreamble), keyEquivalent: "").target = self
        m.addItem(withTitle: "Show preamble file in Finder", action: #selector(revealPreamble), keyEquivalent: "").target = self
        let l = m.addItem(withTitle: "Live preview", action: #selector(toggleLive), keyEquivalent: "")
        l.target = self
        l.state = live ? .on : .off
        let h = m.addItem(withTitle: "Hide after copying", action: #selector(toggleHideAfterCopy), keyEquivalent: "")
        h.target = self
        h.state = hideAfterCopy ? .on : .off
        m.addItem(withTitle: "Preview above the editor", action: #selector(togglePreviewAbove), keyEquivalent: "").target = self
        m.addItem(withTitle: "Line numbers", action: #selector(toggleLineNumbers), keyEquivalent: "").target = self
        let a = m.addItem(withTitle: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        a.target = self
        a.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(withTitle: "Change shortcut (\(shortcut.label))…", action: #selector(changeShortcut), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit eqpop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
    }

    /// Renders the sample, then writes the window (title bar included) to a PNG without ever putting it on screen.
    func screenshot(to path: String) {
        renderNow()
        var waited = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
            guard let self = self else { return }
            waited += 0.2
            let busy = self.status.stringValue.isEmpty || self.status.stringValue == "rendering…"
            guard !busy || waited > 60 else { return }
            t.invalidate()
            self.panel.contentView?.layoutSubtreeIfNeeded()
            guard let frame = self.panel.contentView?.superview, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { exit(1) }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            let out = App.withWindowEdges(rep)
            try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            defaults.removePersistentDomain(forName: "eqpop-screenshot")
            print("wrote \(path) (\(out.pixelsWide) × \(out.pixelsHigh))")
            exit(0)
        }
    }

    /// The captured frame has square corners and no shadow: round it and give it a shadow on a transparent margin.
    static func withWindowEdges(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
        let pad = 60, radius: CGFloat = 26
        let w = rep.pixelsWide + 2 * pad, h = rep.pixelsHigh + 2 * pad
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let box = NSRect(x: pad, y: pad, width: rep.pixelsWide, height: rep.pixelsHigh)
        let shape = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowOffset = NSSize(width: 0, height: -14); sh.shadowBlurRadius = 36
        sh.shadowColor = NSColor.black.withAlphaComponent(0.45)
        sh.set(); NSColor.black.setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        shape.addClip()
        let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)); img.addRepresentation(rep)
        img.draw(in: box)
        NSColor(white: 1, alpha: 0.12).setStroke(); shape.lineWidth = 2; shape.stroke()   // the hairline macOS draws
        NSGraphicsContext.restoreGraphicsState()
        out.size = NSSize(width: w / 2, height: h / 2)   // 2x
        return out
    }

    // MARK: show / hide

    func toggle() { panel.isVisible && NSApp.isActive ? hide() : show() }

    @objc func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(input)
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))   // keep the text: a stray key must not wipe it
        if lastPDF == nil && !selectedEngine.isSlow { schedule(after: 0) }
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
            let file = paneSeg.selectedSegment == 1 ? Store.metadataURL : Store.preambleURL
            try? preambleView.string.write(to: file, atomically: true, encoding: .utf8)   // the file is the source of truth
            changed(after: 0.6)
        } else {
            defaults.set(input.string, forKey: "source")
            changed(after: 0.4)
        }
    }

    @objc func optionsChanged() {
        defaults.set(selectedMode.rawValue, forKey: "mode")
        defaults.set(selectedEngine.rawValue, forKey: "engine")
        defaults.set(pdfmdPopup.titleOfSelectedItem ?? "auto", forKey: "pdfmdEngine")
        applyEngineChoice()
        changed(after: 0)
    }

    /// What depends on the engine: pdfmd takes Markdown (no mode) and has a PDF engine of its own and a metadata tab.
    func applyEngineChoice() {
        let md = selectedEngine == .pdfmd
        modePopup.isEnabled = !md
        pdfmdPopup.isHidden = !md
        paneSeg?.setEnabled(md, forSegment: 1)
        if !md, paneSeg?.selectedSegment == 1 { paneSeg.selectedSegment = 0; loadPane() }
    }

    @objc func paneChanged() { loadPane() }

    /// Shows the file of the selected tab (preamble or pdfmd metadata) in the pane.
    func loadPane() {
        let meta = paneSeg.selectedSegment == 1
        preambleEditing.yaml = meta
        preambleView.string = meta ? Store.metadata() : Store.preamble()
    }

    func makeRequest(_ src: String) -> RenderRequest {
        RenderRequest(source: src, mode: selectedMode, engine: selectedEngine, preamble: Store.preamble(),
                      pdfmdEngine: pdfmdPopup.titleOfSelectedItem ?? "auto", metadata: Store.metadata())
    }

    func jump(toLine line: Int) {
        let s = input.string as NSString
        var start = 0, n = 1
        while n < line, start < s.length {
            let r = s.range(of: "\n", range: NSRange(location: start, length: s.length - start))
            if r.location == NSNotFound { break }
            start = NSMaxRange(r); n += 1
        }
        let range = s.lineRange(for: NSRange(location: min(start, s.length), length: 0))
        panel.makeFirstResponder(input)
        input.setSelectedRange(range)
        input.scrollRangeToVisible(range)
    }

    @objc func showLog() { logWindow.show(lastLog) }

    var selectedMode: Mode { Mode(rawValue: modePopup.selectedItem?.representedObject as? String ?? "") ?? .display }
    var selectedEngine: Engine { Engine(rawValue: enginePopup.titleOfSelectedItem ?? "") ?? .pdflatex }

    /// The input changed: render after a pause when live, else just say that the preview is out of date.
    func changed(after delay: TimeInterval) {
        if live && !selectedEngine.isSlow { schedule(after: delay); return }
        debounce?.invalidate()
        renderer.cancel()
        if selectedEngine.isSlow { setStatus("pdfmd takes a few seconds: ⌘R renders", error: false) }
        else if lastPDF != nil { setStatus("edited: ⌘R renders", error: false) }
    }

    @objc func renderNowAction() { schedule(after: 0) }

    @objc func toggleLive() {
        live.toggle()
        liveBox.state = live ? .on : .off
        defaults.set(live, forKey: "live")
        rebuildMenu()
        if live { schedule(after: 0) } else { debounce?.invalidate() }
    }

    func schedule(after delay: TimeInterval) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.renderNow() }
    }

    func renderNow() {
        let src = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.isEmpty {
            renderer.cancel(); lastPDF = nil; preview.image = nil; setStatus("", error: false)
            errors.scroll.isHidden = true; preview.isHidden = false
            return
        }
        setStatus("rendering…", error: false)
        let started = Date()
        let req = makeRequest(src)
        let key = App.key(req)
        renderer.render(req) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let r):
                let pdf = r.pdf
                self.lastLog = r.log
                self.errors.scroll.isHidden = true
                self.preview.isHidden = false
                self.lastPDF = pdf
                self.lastKey = key
                self.preview.image = NSImage(data: pdf)
                let size = PDFTools.pointSize(pdf).map { String(format: "%.0f × %.0f pt", $0.width, $0.height) } ?? ""
                let more = r.pages > 1 ? " · page 1 of \(r.pages)" : ""
                self.setStatus(String(format: "%@ · %.2f s", size, Date().timeIntervalSince(started)) + more, error: false)
                if self.wantCopy { self.wantCopy = false; self.finishCopy(pdf) }
            case .failure(.cancelled):
                break
            case .failure(.noEngine(let name)):
                self.failed()
                let how = name == "pdfmd" ? "pipx install pdfmd-cli" : "install MacTeX or BasicTeX"
                self.errors.scroll.isHidden = true
                self.preview.isHidden = false
                self.setStatus("\(name) not found (\(how)), or pick another engine.", error: true)
            case .failure(.failed(let f)):
                self.failed()
                self.lastLog = f.log
                self.errors.issues = f.issues
                self.errors.scroll.isHidden = false
                self.preview.isHidden = true
                let n = f.issues.count
                self.setStatus(f.issues.contains { $0.line != nil } ? "\(n) error\(n == 1 ? "" : "s"): double-click a line to jump to it" : "\(n) message\(n == 1 ? "" : "s")", error: true)
            }
        }
    }

    /// A failed render: what is on screen is no longer the current text, and a pending copy must not take it instead.
    func failed() {
        lastKey = nil
        if wantCopy { wantCopy = false; NSSound.beep() }
    }

    /// What a result was made from. pdfmd reads neither the mode nor eqpop's preamble, so they are not part of its key.
    static func key(_ r: RenderRequest) -> String {
        r.engine == .pdfmd ? "pdfmd|\(r.pdfmdEngine)|\(r.preamble)|\(r.metadata)|\(r.source)"
                           : "\(r.mode.rawValue)|\(r.engine.rawValue)|\(r.preamble)|\(r.source)"
    }

    func setStatus(_ s: String, error: Bool) {
        status.stringValue = s
        status.textColor = error ? .systemRed : .secondaryLabelColor
        status.toolTip = error ? s : nil
    }

    // MARK: copy and drag

    @objc func copyRendered() {
        // copy only a result made from exactly what is in the window now; otherwise render again and copy that
        let src = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = App.key(makeRequest(src))
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
        if shown { loadPane() }   // an edit made in another editor is picked up
        let delta = App.preamblePaneHeight + 8
        var f = panel.frame
        f.size.height += shown ? delta : -delta
        f.origin.y -= shown ? delta : -delta   // the top edge stays where it is
        paneBox.isHidden = !shown
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

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { warn("Launch at login: \(error.localizedDescription)") }
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

/// The failed render's errors in place of the preview: line, message, and the text TeX had just read.
final class ErrorList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let scroll = NSScrollView()
    private let table = NSTableView()
    var onJump: ((Int) -> Void)?
    var issues: [Issue] = [] { didSet { table.reloadData() } }

    override init() {
        super.init()
        for (id, title, width) in [("line", "line", 44), ("message", "error message", 250), ("near", "near", 160)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = CGFloat(width)
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(clicked)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
    }

    func numberOfRows(in tableView: NSTableView) -> Int { issues.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let issue = issues[row]
        let id = column?.identifier.rawValue ?? ""
        let text = id == "line" ? (issue.line.map(String.init) ?? "–") : id == "message" ? issue.message : issue.near
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        cell.toolTip = text
        if id != "message" { cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular) }
        if id == "line" { cell.alignment = .right }
        return cell
    }

    @objc private func clicked() {
        let r = table.clickedRow
        if r >= 0, r < issues.count, let line = issues[r].line { onJump?(line) }
    }
}

/// The full log of the last render, for when the list is not enough.
final class LogWindow {
    private let window: NSPanel
    private let text: NSTextView

    init() {
        let scroll = NSTextView.scrollableTextView()
        text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "eqpop log"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.contentView = scroll
        window.setFrameAutosaveName("eqpopLog")
    }

    func show(_ log: String) {
        text.string = log.isEmpty ? "(no log yet)" : log
        text.scrollToEndOfDocument(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
