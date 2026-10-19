// Draws the icon candidates:  swift design/logo.swift design/out   (writes a.png b.png c.png, 1024x1024)
import Cocoa

let S: CGFloat = 1024

func canvas(_ draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: the tile is 824 of 1024, centred
    draw(CGRect(x: 100, y: 100, width: 824, height: 824))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func tile(_ r: CGRect, _ top: NSColor, _ bottom: NSColor) {
    let p = NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185)
    let sh = NSShadow()
    sh.shadowOffset = NSSize(width: 0, height: -12); sh.shadowBlurRadius = 28
    sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
    NSGraphicsContext.saveGraphicsState(); sh.set(); top.setFill(); p.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: top, ending: bottom)!.draw(in: p, angle: -90)
}

func text(_ s: String, font: NSFont, color: NSColor, center: CGPoint, kern: CGFloat = 0) {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let z = a.size()
    a.draw(at: CGPoint(x: center.x - z.width / 2, y: center.y - z.height / 2))
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }

// A: deep blue tile, an italic x with a square: "x²" the way it is set in a book
let a = canvas { r in
    tile(r, rgb(58, 96, 214), rgb(26, 38, 120))
    let serif = NSFont(name: "STIXGeneral-Italic", size: 560) ?? .systemFont(ofSize: 560)
    text("x", font: serif, color: .white, center: CGPoint(x: 450, y: 440))
    let up = NSFont(name: "STIXGeneral-Regular", size: 300) ?? .systemFont(ofSize: 300)
    text("2", font: up, color: rgb(255, 214, 102), center: CGPoint(x: 680, y: 610))
}

// B: pale paper tile, a summoned window: title bar with three dots, the sum sign inside
let b = canvas { r in
    tile(r, rgb(250, 248, 242), rgb(226, 222, 212))
    let w = CGRect(x: 210, y: 250, width: 604, height: 524)
    let win = NSBezierPath(roundedRect: w, xRadius: 56, yRadius: 56)
    rgb(32, 36, 52).setFill(); win.fill()
    for (i, c) in [rgb(255, 95, 86), rgb(255, 189, 46), rgb(39, 201, 63)].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: CGRect(x: 250 + CGFloat(i) * 56, y: 706, width: 34, height: 34)).fill()
    }
    let serif = NSFont(name: "STIXGeneral-Regular", size: 330) ?? .systemFont(ofSize: 330)
    text("∑", font: serif, color: .white, center: CGPoint(x: 512, y: 470))
}

// C: dark tile, the source-and-result idea: a backslash command that turns into the typeset symbol
let c = canvas { r in
    tile(r, rgb(44, 48, 66), rgb(18, 20, 30))
    let mono = NSFont(name: "Menlo-Bold", size: 230) ?? .monospacedSystemFont(ofSize: 230, weight: .bold)
    text("\\eq", font: mono, color: rgb(255, 150, 70), center: CGPoint(x: 512, y: 640))
    let line = NSBezierPath(); line.move(to: CGPoint(x: 250, y: 490)); line.line(to: CGPoint(x: 774, y: 490))
    line.lineWidth = 8; rgb(255, 255, 255, 0.25).setStroke(); line.stroke()
    let serif = NSFont(name: "STIXGeneral-Italic", size: 190) ?? .systemFont(ofSize: 190)
    text("E = mc²", font: serif, color: .white, center: CGPoint(x: 512, y: 340))
}

/// Draws the runs so that the ink (the glyph outlines, not the line box) is centred on `center`.
func rich(_ parts: [(String, NSFont, NSColor)], center: CGPoint) {
    let a = NSMutableAttributedString()
    for (t, f, c) in parts { a.append(NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c])) }
    let line = CTLineCreateWithAttributedString(a)
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
    CTLineDraw(line, ctx)
}
let ital = { (n: CGFloat) in NSFont(name: "STIXGeneral-Italic", size: n) ?? .systemFont(ofSize: n) }
let roman = { (n: CGFloat) in NSFont(name: "STIXGeneral-Regular", size: n) ?? .systemFont(ofSize: n) }
let menlo = { (n: CGFloat) in NSFont(name: "Menlo-Bold", size: n) ?? .monospacedSystemFont(ofSize: n, weight: .bold) }

// D: f(x), as in the menu bar: teal to blue tile, white
let d = canvas { r in
    tile(r, rgb(40, 170, 190), rgb(30, 70, 150))
    rich([("f\u{200A}", ital(380), .white), ("(", roman(380), .white), ("x", ital(380), .white), (")", roman(380), .white)], center: CGPoint(x: 512, y: 512))
}
// E: \ce: the mhchem command, backslash in the editor's blue
let e = canvas { r in
    tile(r, rgb(40, 150, 110), rgb(16, 70, 70))
    rich([("\\", menlo(330), rgb(255, 214, 102)), ("ce", menlo(330), .white)], center: CGPoint(x: 512, y: 500))
}
// F: the integral sign, gold on navy
let f = canvas { r in
    tile(r, rgb(46, 52, 96), rgb(16, 18, 44))
    text("∫", font: roman(640), color: rgb(255, 205, 90), center: CGPoint(x: 512, y: 510))
}
// G: $x$, the math-mode delimiters of TeX
let g = canvas { r in
    tile(r, rgb(92, 62, 170), rgb(40, 26, 100))
    rich([("$", menlo(300), rgb(255, 170, 90)), ("x", ital(380), .white), ("$", menlo(300), rgb(255, 170, 90))], center: CGPoint(x: 512, y: 500))
}
// H: f(x) on paper, ink-dark with a red underline
let h = canvas { r in
    tile(r, rgb(252, 250, 244), rgb(228, 224, 212))
    let ink = rgb(30, 34, 60)
    rich([("f", ital(380), ink), ("(", roman(380), ink), ("x", ital(380), ink), (")", roman(380), ink)], center: CGPoint(x: 512, y: 520))
    let u = NSBezierPath(roundedRect: CGRect(x: 262, y: 262, width: 500, height: 26), xRadius: 13, yRadius: 13)
    rgb(220, 70, 60).setFill(); u.fill()
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/out"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let all: [(String, NSBitmapImageRep)] = [("a", a), ("d", d), ("e", e), ("f", f), ("g", g), ("h", h)]
for (name, rep) in all {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
// a contact sheet: each at 300 px, then a 64 px and a 32 px copy under it, as the Dock and Spotlight show them
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300 * all.count, pixelsHigh: 470, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(white: 0.93, alpha: 1).setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: sheet.pixelsWide, height: 470)).fill()
for (i, (name, rep)) in all.enumerated() {
    let img = NSImage(size: NSSize(width: S, height: S)); img.addRepresentation(rep)
    let x = CGFloat(i) * 300
    img.draw(in: CGRect(x: x, y: 170, width: 300, height: 300))
    img.draw(in: CGRect(x: x + 60, y: 70, width: 64, height: 64))
    img.draw(in: CGRect(x: x + 160, y: 86, width: 32, height: 32))
    text(name.uppercased(), font: .boldSystemFont(ofSize: 22), color: .black, center: CGPoint(x: x + 150, y: 30))
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/sheet.png"))
print("wrote \(dir)")
