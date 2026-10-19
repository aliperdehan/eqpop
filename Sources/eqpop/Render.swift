import Foundation

enum Mode: String, CaseIterable {
    case display, inline, text
    var title: String {
        switch self {
        case .display: return "Display math"
        case .inline: return "Inline math"
        case .text: return "Text (LaTeX)"
        }
    }
}

enum Engine: String, CaseIterable {
    case pdflatex, lualatex, xelatex
    /// Markdown through pdfmd (Pandoc and its own engine chain): the source is a Markdown document, not LaTeX.
    case pdfmd
    /// Too slow to render while typing (seconds, not a fraction of one).
    var isSlow: Bool { self == .pdfmd }
}

/// What pdfmd's `-e` is given: "auto" leaves the choice to pdfmd, the rest name an engine or a family.
let pdfmdEngines = ["auto", "tex", "lualatex", "pdflatex", "xelatex", "typst", "html"]

struct RenderRequest {
    var source: String
    var mode: Mode
    var engine: Engine
    var preamble: String
    var pdfmdEngine = "auto"
    var metadata = ""   // pdfmd only: the YAML written beside the snippet as metadata.yaml
}

/// A finished render: the page, cropped to its ink; how many pages the engine made (only the first is kept); its log.
struct Rendered {
    var pdf: Data
    var pages: Int
    var log: String
}

/// One line of the error list. `line` counts lines of the user's own source; nil means the error is not in it
/// (in the preamble, or a message of pdfmd's). `near` is the text TeX had just read.
struct Issue {
    var line: Int?
    var message: String
    var near = ""
}

struct Failure {
    var issues: [Issue]
    var log: String
}

enum RenderError: Error {
    case noEngine(String)
    case failed(Failure)
    case cancelled
}

/// The document handed to the engine. `standalone` crops the page to the content, so no pdfcrop step is needed;
/// `varwidth` puts the content in a vertical-mode box, which lets `\[ \]` and `align*` work.
enum Wrapper {
    private static let ownsMath = try! NSRegularExpression(
        pattern: #"^\s*(\\\[|\$\$)|\\begin\{(equation|align|alignat|flalign|gather|multline|eqnarray|displaymath|math)\*?\}"#)

    private static func wraps(_ s: String, _ mode: Mode) -> Bool {
        mode == .display && ownsMath.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) == nil
    }

    static func body(_ source: String, _ mode: Mode) -> String {
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .text: return s
        case .inline: return "\\(" + s + "\\)"
        case .display: return wraps(s, mode) ? "\\[\n" + s + "\n\\]" : s
        }
    }

    /// How many lines the content block puts before the first line of the user's source.
    static func linesBeforeSource(_ source: String, _ mode: Mode) -> Int {
        wraps(source.trimmingCharacters(in: .whitespacesAndNewlines), mode) ? 1 : 0
    }

    static let header = "\\documentclass[border=2pt,varwidth=16cm]{standalone}\n"

    /// Everything the engine reads before the content: what a cached format holds.
    static func preambleText(_ preamble: String) -> String { header + preamble + "\n\\begin{document}\n" }

    static func content(_ r: RenderRequest) -> String { body(r.source, r.mode) + "\n\\end{document}\n" }

    static func document(_ r: RenderRequest) -> String { preambleText(r.preamble) + content(r) }

    /// The Markdown file pdfmd builds: no page number in a LaTeX build (the crop leaves out the bottom margin for the
    /// others).
    static func markdown(_ source: String) -> String {
        "---\npagestyle: empty\nheader-includes:\n  - \\pagestyle{empty}\n---\n\n"
            + source.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Every "! ..." error of a TeX log. `prefix` is the number of file lines before the content block (it differs
    /// between the full document and a run from a cached format), to turn TeX's line numbers into the user's.
    static func issues(log: String, source: String, mode: Mode, prefix: Int) -> [Issue] {
        let lines = log.components(separatedBy: "\n")
        let sourceLines = max(1, source.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").count)
        let leading = source.prefix(while: { $0.isWhitespace }).filter { $0 == "\n" }.count   // dropped by the trim
        let offset = prefix + linesBeforeSource(source, mode)
        var out: [Issue] = []
        for (i, l) in lines.enumerated() where l.hasPrefix("! ") && out.count < 30 {
            let message = l.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if message.hasPrefix("==> Fatal error") || message.hasPrefix("Emergency stop") { continue }
            var issue = Issue(line: nil, message: message)
            for j in (i + 1)..<min(i + 12, lines.count) where lines[j].hasPrefix("l.") {
                let digits = lines[j].dropFirst(2).prefix(while: { $0.isNumber })
                if let n = Int(digits) {
                    let u = n - offset
                    issue.line = u < 1 ? nil : min(u, sourceLines) + leading   // `\]` closes below the last line
                    if u < 1 { issue.message = "(preamble) " + message }
                }
                let near = lines[j].dropFirst(2).drop(while: { $0.isNumber }).trimmingCharacters(in: .whitespaces)
                issue.near = near.hasPrefix("^^") ? "" : near   // a bare line end, not text
                break
            }
            out.append(issue)
        }
        return out
    }

    /// The last lines pdfmd printed, one issue each, when it fails.
    static func pdfmdIssues(log: String) -> [Issue] {
        let lines = log.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.suffix(6).map { Issue(line: nil, message: $0) }
    }
}

/// One render at a time: a new request ends the one in flight, whose result is then reported as cancelled.
final class Renderer {
    private let lock = NSLock()
    private var generation = 0
    private var running: Process?
    private let queue = DispatchQueue(label: "eqpop.render", qos: .userInitiated)

    private func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        running?.terminate()
        return generation
    }

    func cancel() { _ = next() }

    func render(_ req: RenderRequest, completion: @escaping (Result<Rendered, RenderError>) -> Void) {
        let gen = next()
        queue.async {
            let result = self.work(req, gen)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func renderSync(_ req: RenderRequest) -> Result<Rendered, RenderError> { work(req, next()) }

    /// Runs one process to its end. nil if a newer request (or the time limit) ended it.
    private func run(_ exe: String, _ args: [String], in dir: URL, env: [String: String], gen: Int,
                     timeout: TimeInterval = 30, output: URL? = nil) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        if let out = output {   // stdout and stderr to a file the caller reads
            FileManager.default.createFile(atPath: out.path, contents: nil)
            if let h = try? FileHandle(forWritingTo: out) { p.standardOutput = h; p.standardError = h }
        }
        lock.lock()
        if gen != generation { lock.unlock(); return nil }
        do { try p.run() } catch { lock.unlock(); return -1 }
        running = p
        lock.unlock()
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        lock.lock()
        if running === p { running = nil }
        let stale = gen != generation
        lock.unlock()
        return stale ? nil : p.terminationStatus
    }

    private func folderError(_ error: Error) -> Result<Rendered, RenderError> {
        .failure(.failed(Failure(issues: [Issue(line: nil, message: "cannot write the work folder: \(error.localizedDescription)")], log: "")))
    }

    private func workMarkdown(_ req: RenderRequest, _ gen: Int) -> Result<Rendered, RenderError> {
        guard let cmd = Toolchain.pdfmdCommand() else { return .failure(.noEngine("pdfmd")) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("eqpop-" + UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Wrapper.markdown(req.source).write(to: dir.appendingPathComponent("snippet.md"), atomically: true, encoding: .utf8)
            // pdfmd finds these beside the source, as it does in a project folder
            try req.preamble.write(to: dir.appendingPathComponent("preamble.tex"), atomically: true, encoding: .utf8)
            try req.metadata.write(to: dir.appendingPathComponent("metadata.yaml"), atomically: true, encoding: .utf8)
        } catch { return folderError(error) }
        defer { try? fm.removeItem(at: dir) }
        let log = dir.appendingPathComponent("pdfmd.log")
        var args = cmd.args + ["snippet.md"]
        if req.pdfmdEngine != "auto" { args += ["-e", req.pdfmdEngine] }
        guard let status = run(cmd.exe, args, in: dir, env: Toolchain.environment, gen: gen, timeout: 120, output: log)
        else { return .failure(.cancelled) }
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        if status == 0, let pdf = try? Data(contentsOf: dir.appendingPathComponent("snippet.pdf")) {
            let r = PDFTools.tight(pdf, ignoreBottom: 66)
            return .success(Rendered(pdf: r.pdf, pages: r.pages, log: text))
        }
        let issues = Wrapper.pdfmdIssues(log: text)
        return .failure(.failed(Failure(issues: issues.isEmpty ? [Issue(line: nil, message: "pdfmd failed or timed out")] : issues, log: text)))
    }

    private func work(_ req: RenderRequest, _ gen: Int) -> Result<Rendered, RenderError> {
        if req.engine == .pdfmd { return workMarkdown(req, gen) }
        let name = req.engine.rawValue
        guard let exe = Toolchain.find(name) else { return .failure(.noEngine(name)) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("eqpop-" + UUID().uuidString, isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return folderError(error) }
        defer { try? fm.removeItem(at: dir) }
        let tex = dir.appendingPathComponent("snippet.tex"), log = dir.appendingPathComponent("snippet.log")
        // no -halt-on-error: the error list shows every error of the snippet, as LaTeXiT's does
        let args = ["-interaction=nonstopmode", "-no-shell-escape"]

        // fast path: the packages and the preamble are already compiled into a cached format
        if let fmt = FormatCache.ready(req) {
            try? ("\\begin{document}\n" + Wrapper.content(req)).write(to: tex, atomically: true, encoding: .utf8)
            var env = Toolchain.environment
            env["TEXFORMATS"] = fmt.path + ":"
            guard let status = run(exe, args + ["-fmt=eqpop", "snippet.tex"], in: dir, env: env, gen: gen) else { return .failure(.cancelled) }
            if fm.fileExists(atPath: log.path) {   // no log at all means the format itself did not load (stale or broken)
                return finish(status, dir, req, prefix: 1)
            }
            FormatCache.discard(req)
            try? fm.removeItem(at: dir.appendingPathComponent("snippet.pdf"))
        }

        do { try Wrapper.document(req).write(to: tex, atomically: true, encoding: .utf8) } catch { return folderError(error) }
        guard let status = run(exe, args + ["snippet.tex"], in: dir, env: Toolchain.environment, gen: gen) else { return .failure(.cancelled) }
        let prefix = Wrapper.preambleText(req.preamble).filter { $0 == "\n" }.count
        let result = finish(status, dir, req, prefix: prefix)
        if case .success = result { FormatCache.buildInBackground(req) }
        return result
    }

    private func finish(_ status: Int32, _ dir: URL, _ req: RenderRequest, prefix: Int) -> Result<Rendered, RenderError> {
        let log = (try? String(contentsOf: dir.appendingPathComponent("snippet.log"), encoding: .utf8)) ?? ""
        if status == 0, let pdf = try? Data(contentsOf: dir.appendingPathComponent("snippet.pdf")) {
            let r = PDFTools.tight(pdf)
            return .success(Rendered(pdf: r.pdf, pages: r.pages, log: log))
        }
        var issues = Wrapper.issues(log: log, source: req.source, mode: req.mode, prefix: prefix)
        if issues.isEmpty { issues = [Issue(line: nil, message: "\(req.engine.rawValue) failed or timed out")] }
        return .failure(.failed(Failure(issues: issues, log: log)))
    }
}
