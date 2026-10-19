import Cocoa

/// A gutter with the line numbers of a text view (numbers of lines, not of wrapped rows: a wrapped line is numbered once).
final class LineNumbers: NSRulerView {
    private weak var textView: NSTextView?

    init(_ scroll: NSScrollView, _ tv: NSTextView) {
        textView = tv
        super.init(scrollView: scroll, orientation: .verticalRuler)
        clientView = tv
        ruleThickness = 30
        clipsToBounds = true
        scroll.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        nc.addObserver(self, selector: #selector(redraw), name: NSText.didChangeNotification, object: tv)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                                                    .foregroundColor: NSColor.tertiaryLabelColor]
        let text = tv.string as NSString
        let origin = tv.textContainerOrigin

        func draw(_ n: Int, atFragment r: NSRect) {
            let label = NSAttributedString(string: String(n), attributes: attrs)
            let y = convert(NSPoint(x: 0, y: r.minY + origin.y), from: tv).y
            label.draw(at: NSPoint(x: ruleThickness - 5 - label.size().width, y: y + (r.height - label.size().height) / 2))
        }

        func lineNumber(at loc: Int) -> Int {   // newlines before it, plus one; the texts here hold a few lines
            var n = 1
            for i in 0..<loc where text.character(at: i) == 0x0A { n += 1 }
            return n
        }

        let glyphs = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        lm.enumerateLineFragments(forGlyphRange: glyphs) { r, _, _, g, _ in
            let loc = lm.characterRange(forGlyphRange: g, actualGlyphRange: nil).location
            if loc == 0 || text.character(at: loc - 1) == 0x0A { draw(lineNumber(at: loc), atFragment: r) }
        }
        if text.length == 0 || text.character(at: text.length - 1) == 0x0A {   // the empty last line has no fragment of its own
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 { draw(lineNumber(at: text.length), atFragment: extra) }
        }
    }
}
