import Cocoa
import PDFKit

/// The rendered result is a vector PDF; these turn it into what a paste target may want.
enum PDFTools {
    static func pointSize(_ pdf: Data) -> NSSize? { NSPDFImageRep(data: pdf)?.bounds.size }

    /// The page drawn on a transparent bitmap at `scale` pixels per point.
    private static func bitmap(_ rep: NSPDFImageRep, scale: CGFloat) -> NSBitmapImageRep? {
        let size = rep.bounds.size
        let w = max(1, Int((size.width * scale).rounded(.up)))
        let h = max(1, Int((size.height * scale).rounded(.up)))
        guard let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: bmp) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let frame = NSRect(x: 0, y: 0, width: w, height: h)
        NSColor.clear.set()
        frame.fill(using: .copy)
        rep.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
        return bmp
    }

    /// A transparent PNG drawn from the PDF at `scale` pixels per point (4 = 288 dpi).
    static func png(from pdf: Data, scale: CGFloat = 4) -> Data? {
        guard let rep = NSPDFImageRep(data: pdf), let bmp = bitmap(rep, scale: scale) else { return nil }
        bmp.size = rep.bounds.size   // pixels stay as drawn; the size in points gives the right dpi
        return bmp.representation(using: .png, properties: [:])
    }

    /// Crops the first page to what is drawn on it, plus `pad` points. The engines crop to a box, which is not always
    /// the ink (`align*` is as wide as the line); the ink is found on a bitmap, so this works for any engine's PDF
    /// and needs no tool. The page stays vector: only its boxes change.
    static func tight(_ pdf: Data, pad: CGFloat = 2) -> Data? {
        let scale: CGFloat = 4
        guard let rep = NSPDFImageRep(data: pdf), let bmp = bitmap(rep, scale: scale), let px = bmp.bitmapData,
              let doc = PDFDocument(data: pdf), let page = doc.page(at: 0) else { return nil }
        var minX = bmp.pixelsWide, maxX = -1, minY = bmp.pixelsHigh, maxY = -1
        for y in 0..<bmp.pixelsHigh {
            let row = px + y * bmp.bytesPerRow
            for x in 0..<bmp.pixelsWide where row[x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= 0 else { return pdf }   // nothing drawn: leave the page as it is
        let media = page.bounds(for: .mediaBox)
        let ink = CGRect(x: media.minX + CGFloat(minX) / scale,
                         y: media.maxY - CGFloat(maxY + 1) / scale,
                         width: CGFloat(maxX - minX + 1) / scale,
                         height: CGFloat(maxY - minY + 1) / scale)
        let box = ink.insetBy(dx: -pad, dy: -pad).intersection(media)
        page.setBounds(box, for: .mediaBox)
        page.setBounds(box, for: .cropBox)
        return doc.dataRepresentation()
    }

    /// The page as SVG, through poppler's `pdftocairo` or else MuPDF's `mutool` (Homebrew: poppler, mupdf-tools).
    /// nil when neither is installed.
    static func svg(from pdf: Data) -> Data? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("eqpop-svg-" + UUID().uuidString, isDirectory: true)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? fm.removeItem(at: dir) }
        let src = dir.appendingPathComponent("in.pdf"), out = dir.appendingPathComponent("out.svg")
        guard (try? pdf.write(to: src)) != nil else { return nil }
        if let t = Toolchain.find("pdftocairo") {
            _ = Toolchain.run(t, ["-svg", src.path, out.path])
        } else if let m = Toolchain.find("mutool") {
            _ = Toolchain.run(m, ["convert", "-o", out.path, src.path])
        }
        return try? Data(contentsOf: out)
    }

    /// PDF for apps that take vector, PNG for those that do not; the receiving app picks the better one.
    static func copyToClipboard(_ pdf: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pdf, forType: .pdf)
        if let png = png(from: pdf) { pb.setData(png, forType: .png) }
    }
}
