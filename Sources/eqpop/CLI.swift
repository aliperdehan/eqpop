import Foundation

/// `eqpop --render 'SNIPPET' out.pdf [--inline|--text] [--engine pdflatex|lualatex|xelatex|pdfmd] [--pdfmd-engine E] [--metadata FILE] [--preamble FILE] [--png FILE] [--svg FILE] [--warm]`
/// runs the same pipeline as the window, without one (for scripts and for testing).
func cliRender(_ args: [String]) -> Int32 {
    var positional: [String] = []
    var mode = Mode.display
    var engine = Engine.pdflatex
    var preamble: String?
    var pngPath: String?
    var svgPath: String?
    var warm = false
    var pdfmdEngine = "auto"
    var metadata: String?
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--display": mode = .display
        case "--inline": mode = .inline
        case "--text": mode = .text
        case "--warm": warm = true
        case "--engine", "--preamble", "--png", "--svg", "--pdfmd-engine", "--metadata":
            guard i + 1 < args.count else { FileHandle.standardError.write(Data("eqpop: \(args[i]) needs a value\n".utf8)); return 2 }
            i += 1
            if args[i - 1] == "--pdfmd-engine" {
                pdfmdEngine = args[i]
            } else if args[i - 1] == "--metadata" {
                metadata = try? String(contentsOfFile: (args[i] as NSString).expandingTildeInPath, encoding: .utf8)
            } else if args[i - 1] == "--png" {
                pngPath = (args[i] as NSString).expandingTildeInPath
            } else if args[i - 1] == "--svg" {
                svgPath = (args[i] as NSString).expandingTildeInPath
            } else if args[i - 1] == "--engine" {
                guard let e = Engine(rawValue: args[i]) else { FileHandle.standardError.write(Data("eqpop: unknown engine \(args[i])\n".utf8)); return 2 }
                engine = e
            } else {
                guard let text = try? String(contentsOfFile: (args[i] as NSString).expandingTildeInPath, encoding: .utf8) else {
                    FileHandle.standardError.write(Data("eqpop: cannot read \(args[i])\n".utf8)); return 2
                }
                preamble = text
            }
        default: positional.append(args[i])
        }
        i += 1
    }
    guard positional.count == 2 else {
        FileHandle.standardError.write(Data("usage: eqpop --render SNIPPET OUT.pdf [--inline|--text] [--engine E] [--preamble FILE] [--png FILE] [--svg FILE] [--warm]\n".utf8))
        return 2
    }
    let req = RenderRequest(source: positional[0], mode: mode, engine: engine, preamble: preamble ?? Store.preamble(),
                            pdfmdEngine: pdfmdEngine, metadata: metadata ?? Store.metadata())
    switch Renderer().renderSync(req) {
    case .success(let rendered):
        let pdf = rendered.pdf
        if rendered.pages > 1 { FileHandle.standardError.write(Data("eqpop: the engine made \(rendered.pages) pages; only the first is kept\n".utf8)) }
        if warm { FormatCache.waitIdle() }   // lets the cached preamble finish, so the next run is fast
        do {
            try pdf.write(to: URL(fileURLWithPath: (positional[1] as NSString).expandingTildeInPath))
            if let path = pngPath {
                guard let png = PDFTools.png(from: pdf) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: URL(fileURLWithPath: path))
            }
            if let path = svgPath {
                guard let svg = PDFTools.svg(from: pdf) else {
                    FileHandle.standardError.write(Data("eqpop: SVG needs pdftocairo (brew install poppler) or mutool (brew install mupdf-tools)\n".utf8)); return 1
                }
                try svg.write(to: URL(fileURLWithPath: path))
            }
        } catch {
            FileHandle.standardError.write(Data("eqpop: \(error.localizedDescription)\n".utf8)); return 1
        }
        return 0
    case .failure(.noEngine(let name)):
        FileHandle.standardError.write(Data("eqpop: \(name) not found\n".utf8)); return 1
    case .failure(.failed(let f)):
        for issue in f.issues {
            let at = issue.line.map { "line \($0): " } ?? ""
            FileHandle.standardError.write(Data("eqpop: \(at)\(issue.message)\(issue.near.isEmpty ? "" : "   near: " + issue.near)\n".utf8))
        }
        return 1
    case .failure(.cancelled):
        return 1
    }
}

/// `eqpop --selftest`: checks of the pure pieces (bracket pairing, the wrapper), needing no TeX.
func selfTest() -> Int32 {
    var failures = 0
    func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL: \(what)") } }
    let s = "a{b[c]\\}d}(e" as NSString   // 0:a 1:{ 2:b 3:[ 4:c 5:] 6:\ 7:} 8:d 9:} 10:( 11:e
    check(TeXEditing.partner(of: 1, in: s) == 9, "{ pairs with the last }, skipping the escaped \\}")
    check(TeXEditing.partner(of: 9, in: s) == 1, "} pairs back to {")
    check(TeXEditing.partner(of: 3, in: s) == 5, "[ pairs with ]")
    check(TeXEditing.partner(of: 5, in: s) == 3, "] pairs with [")
    check(TeXEditing.partner(of: 7, in: s) == nil, "an escaped brace has no partner")
    check(TeXEditing.partner(of: 10, in: s) == nil, "an unclosed ( has no partner")
    check(Wrapper.body("x^2", .display) == "\\[\nx^2\n\\]", "display wraps plain math in \\[ \\]")
    check(Wrapper.body("\\begin{align*}a&=b\\end{align*}", .display).hasPrefix("\\begin{align*}"), "align* is left to bring its own math mode")
    check(Wrapper.body("\\begin{pmatrix}1\\end{pmatrix}", .display).hasPrefix("\\["), "a matrix inside display math is still wrapped")
    check(Wrapper.body("x", .inline) == "\\(x\\)", "inline wraps in \\( \\)")
    check(Wrapper.markdown("# Hi\n").contains("pagestyle{empty}") && Wrapper.markdown("# Hi\n").hasSuffix("# Hi\n"), "the Markdown wrapper hides the page number and keeps the source")
    // file: 1 \documentclass, 2 \begin{document}... with prefix 1 (cached format): 2 `\[`, 3 first source line, 4 `\]`
    let log = "! Undefined control sequence.\n<argument> \\foo \nl.3 \\foo\n\n! Missing $ inserted.\nl.3 x\n"
    let found = Wrapper.issues(log: log, source: "\\foo", mode: .display, prefix: 1)
    check(found.count == 2, "both errors of a log are listed")
    check(found.first?.line == 1 && found.first?.near == "\\foo", "an error on the first source line is line 1, with its text")
    let pre = Wrapper.issues(log: "! Undefined control sequence.\nl.2 \\usepackage\n", source: "x", mode: .text, prefix: 3)
    check(pre.first?.line == nil && pre.first?.message.hasPrefix("(preamble)") == true, "an error above the source is marked as the preamble's")
    let closing = Wrapper.issues(log: "! Undefined control sequence.\nl.4 \\]\n", source: "\\foo", mode: .display, prefix: 1)
    check(closing.first?.line == 1, "an error reported at the closing \\] points at the last source line")
    let skipped = Wrapper.issues(log: "! Undefined control sequence.\nl.2 x\n", source: "\n\nx", mode: .text, prefix: 1)
    check(skipped.first?.line == 3, "blank lines trimmed from the top of the source still count")
    print(failures == 0 ? "selftest ok" : "\(failures) failed")
    return failures == 0 ? 0 : 1
}
