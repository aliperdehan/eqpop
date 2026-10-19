import Foundation

let eqpopVersion = "0.1.1"

/// What the app keeps on disk. The preamble is a plain file the user owns: it is written once, when missing, and
/// never overwritten by the app; every render reads it from disk, so an edit in any editor counts at once.
enum Store {
    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("eqpop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("eqpop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var preambleURL: URL { appSupport.appendingPathComponent("preamble.tex") }

    static let defaultPreamble = """
    % eqpop preamble: loaded before every snippet (no \\documentclass here; the class is standalone).
    % This file is yours. eqpop creates it once and never overwrites it.
    \\usepackage{amsmath,amssymb,bm}
    \\usepackage[version=4]{mhchem}
    \\usepackage{siunitx}
    \\usepackage{xcolor}
    % \\usepackage{chemfig}
    % \\newcommand{\\R}{\\mathbb{R}}

    """

    static var metadataURL: URL { appSupport.appendingPathComponent("pdfmd-metadata.yaml") }

    static let defaultMetadata = """
    # eqpop: metadata for the pdfmd engine. It is written beside every Markdown snippet as metadata.yaml, where
    # pdfmd finds it like a project's own. This file is yours: eqpop creates it once and never overwrites it.
    # pdfmd-options:
    #   engine: typst
    # mainfont: STIX Two Text

    """

    static func metadata() -> String {
        if !FileManager.default.fileExists(atPath: metadataURL.path) {
            try? defaultMetadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        }
        return (try? String(contentsOf: metadataURL, encoding: .utf8)) ?? defaultMetadata
    }

    static func preamble() -> String {
        if !FileManager.default.fileExists(atPath: preambleURL.path) {
            try? defaultPreamble.write(to: preambleURL, atomically: true, encoding: .utf8)
        }
        return (try? String(contentsOf: preambleURL, encoding: .utf8)) ?? defaultPreamble
    }
}
