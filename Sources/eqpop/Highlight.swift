import Cocoa

/// Colours for LaTeX source in a text view, and a highlight on the bracket that pairs with the one at the cursor.
/// Plain regular expressions over the whole text: the editors hold a few lines, so there is nothing to optimise.
final class TeXEditing: NSObject, NSTextStorageDelegate {
    private static let rules: [(NSRegularExpression, NSColor)] = {
        func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
        return [
            (re(#"\\([A-Za-z@]+\*?|.)"#), .systemBlue),     // \command, \\ and \{ alike
            (re(#"[{}\[\]]"#), .systemOrange),
            (re(#"\$+|\\[()\[\]]"#), .systemPurple),         // math delimiters
            (re(#"(?<!\\)%[^\n]*"#), .systemGreen),          // comments last: they win over what is inside them
        ]
    }()

    private weak var textView: NSTextView?
    private var marked: [NSRange] = []

    init(_ tv: NSTextView) {
        textView = tv
        super.init()
        tv.textStorage?.delegate = self
        if let ts = tv.textStorage { colour(ts) }   // text that was there before this was attached
    }

    func textStorage(_ ts: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
        guard mask.contains(.editedCharacters) else { return }
        colour(ts)
    }

    private func colour(_ ts: NSTextStorage) {
        let all = NSRange(location: 0, length: ts.length)
        ts.addAttribute(.foregroundColor, value: NSColor.textColor, range: all)
        let text = ts.string
        for (re, color) in TeXEditing.rules {
            re.enumerateMatches(in: text, range: all) { m, _, _ in
                if let r = m?.range { ts.addAttribute(.foregroundColor, value: color, range: r) }
            }
        }
    }

    /// The index of the bracket that pairs with the one at `i`, nil if there is none; escaped brackets (`\{`) do not count.
    static func partner(of i: Int, in s: NSString) -> Int? {
        let pairs: [unichar: unichar] = [0x7B: 0x7D, 0x5B: 0x5D, 0x28: 0x29, 0x7D: 0x7B, 0x5D: 0x5B, 0x29: 0x28]   // { [ ( and back
        func escaped(_ k: Int) -> Bool {
            var n = 0, j = k - 1
            while j >= 0 && s.character(at: j) == 0x5C { n += 1; j -= 1 }
            return n % 2 == 1
        }
        guard i >= 0, i < s.length, let other = pairs[s.character(at: i)], !escaped(i) else { return nil }
        let open = s.character(at: i)
        let forward = [0x7B, 0x5B, 0x28].contains(open)   // an opening bracket looks right, a closing one left
        var depth = 0, k = i
        while k >= 0 && k < s.length {
            let c = s.character(at: k)
            if !escaped(k) {
                if c == open { depth += 1 } else if c == other { depth -= 1; if depth == 0 { return k } }
            }
            k += forward ? 1 : -1
        }
        return nil
    }

    /// Call when the selection moves: marks the bracket next to the cursor and its partner (red if it has none).
    func updateBrackets() {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        for r in marked where NSMaxRange(r) <= (tv.string as NSString).length { lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r) }
        marked = []
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return }
        let s = tv.string as NSString
        for i in [sel.location - 1, sel.location] where i >= 0 && i < s.length {
            let c = s.character(at: i)
            guard "{}[]()".utf16.contains(c) else { continue }
            let ok = TeXEditing.partner(of: i, in: s)
            let color: NSColor = ok == nil ? NSColor.systemRed.withAlphaComponent(0.45) : NSColor.systemYellow.withAlphaComponent(0.4)
            for k in [i] + (ok.map { [$0] } ?? []) {
                let r = NSRange(location: k, length: 1)
                lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r)
                marked.append(r)
            }
            return
        }
    }
}
