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
}

struct RenderRequest {
    var source: String
    var mode: Mode
    var engine: Engine
    var preamble: String
}

enum RenderError: Error {
    case noEngine(String)
    case failed(String)
    case cancelled
}

/// The document handed to the engine. `standalone` crops the page to the content, so no pdfcrop step is needed;
/// `varwidth` puts the content in a vertical-mode box, which lets `\[ \]` and `align*` work.
enum Wrapper {
    private static let ownsMath = try! NSRegularExpression(
        pattern: #"^\s*(\\\[|\$\$)|\\begin\{(equation|align|alignat|flalign|gather|multline|eqnarray|displaymath|math)\*?\}"#)

    static func body(_ source: String, _ mode: Mode) -> String {
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .text: return s
        case .inline: return "\\(" + s + "\\)"
        case .display:
            let whole = NSRange(s.startIndex..., in: s)
            if ownsMath.firstMatch(in: s, range: whole) != nil { return s }
            return "\\[\n" + s + "\n\\]"
        }
    }

    static let header = "\\documentclass[border=2pt,varwidth=16cm]{standalone}\n"

    /// Everything the engine reads before the content: what a cached format holds.
    static func preambleText(_ preamble: String) -> String { header + preamble + "\n\\begin{document}\n" }

    static func content(_ r: RenderRequest) -> String { body(r.source, r.mode) + "\n\\end{document}\n" }

    static func document(_ r: RenderRequest) -> String { preambleText(r.preamble) + content(r) }

    /// The first "! ..." line of a TeX log with the "l.N ..." line that shows where it stopped.
    static func errorText(log: String) -> String {
        let lines = log.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { $0.hasPrefix("! ") }) else { return "TeX failed (no message in the log)" }
        var out = [String(lines[i].dropFirst(2))]
        let after = lines[(i + 1)...].prefix(8)
        // TeX reports `\[ ... \]` at the closing line; the line above it ("<argument> ...") shows the text at fault
        if let c = after.first(where: { $0.hasPrefix("<") }) { out.append(c) }
        if let l = after.first(where: { $0.hasPrefix("l.") }) { out.append(l) }
        return out.joined(separator: "\n")
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

    func render(_ req: RenderRequest, completion: @escaping (Result<Data, RenderError>) -> Void) {
        let gen = next()
        queue.async {
            let result = self.work(req, gen)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func renderSync(_ req: RenderRequest) -> Result<Data, RenderError> { work(req, next()) }

    /// Runs one TeX process to its end. nil if a newer request (or the 30 s limit) ended it.
    private func runTeX(_ exe: String, _ args: [String], in dir: URL, env: [String: String], gen: Int) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        lock.lock()
        if gen != generation { lock.unlock(); return nil }
        do { try p.run() } catch { lock.unlock(); return -1 }
        running = p
        lock.unlock()
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        lock.lock()
        if running === p { running = nil }
        let stale = gen != generation
        lock.unlock()
        return stale ? nil : p.terminationStatus
    }

    private func work(_ req: RenderRequest, _ gen: Int) -> Result<Data, RenderError> {
        let name = req.engine.rawValue
        guard let exe = Toolchain.find(name) else { return .failure(.noEngine(name)) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("eqpop-" + UUID().uuidString, isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { return .failure(.failed("cannot write the work folder: \(error.localizedDescription)")) }
        defer { try? fm.removeItem(at: dir) }
        let tex = dir.appendingPathComponent("snippet.tex"), log = dir.appendingPathComponent("snippet.log")
        let args = ["-interaction=nonstopmode", "-halt-on-error", "-no-shell-escape"]

        // fast path: the packages and the preamble are already compiled into a cached format
        if let fmt = FormatCache.ready(req) {
            try? ("\\begin{document}\n" + Wrapper.content(req)).write(to: tex, atomically: true, encoding: .utf8)
            var env = Toolchain.environment
            env["TEXFORMATS"] = fmt.path + ":"
            guard let status = runTeX(exe, args + ["-fmt=eqpop", "snippet.tex"], in: dir, env: env, gen: gen) else { return .failure(.cancelled) }
            if fm.fileExists(atPath: log.path) {   // no log at all means the format itself did not load (stale or broken)
                return finish(status, dir, name)
            }
            FormatCache.discard(req)
            try? fm.removeItem(at: dir.appendingPathComponent("snippet.pdf"))
        }

        do { try Wrapper.document(req).write(to: tex, atomically: true, encoding: .utf8) }
        catch { return .failure(.failed("cannot write the work folder: \(error.localizedDescription)")) }
        guard let status = runTeX(exe, args + ["snippet.tex"], in: dir, env: Toolchain.environment, gen: gen) else { return .failure(.cancelled) }
        let result = finish(status, dir, name)
        if case .success = result { FormatCache.buildInBackground(req) }
        return result
    }

    private func finish(_ status: Int32, _ dir: URL, _ name: String) -> Result<Data, RenderError> {
        if status == 0, let pdf = try? Data(contentsOf: dir.appendingPathComponent("snippet.pdf")) {
            return .success(PDFTools.tight(pdf) ?? pdf)
        }
        let log = (try? String(contentsOf: dir.appendingPathComponent("snippet.log"), encoding: .utf8)) ?? ""
        return .failure(.failed(log.isEmpty ? "\(name) failed or timed out" : Wrapper.errorText(log: log)))
    }
}
