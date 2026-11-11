// Labelled contact sheet for the README: swift scripts/contact_sheet.swift out.jpg COLS TILEW "Label=path" ...
import AppKit
let a = CommandLine.arguments
let out = a[1], cols = Int(a[2])!, tileW = CGFloat(Double(a[3])!)
let items: [(String, NSImage)] = a[4...].map { s in
    let p = s.split(separator: "=", maxSplits: 1).map(String.init)
    return (p[0], NSImage(contentsOfFile: p[1])!)
}
let aspect = items[0].1.size.height / items[0].1.size.width
let label: CGFloat = 22, gap: CGFloat = 8
let tileH = tileW * aspect
let rows = (items.count + cols - 1) / cols
let W = CGFloat(cols) * tileW + CGFloat(cols + 1) * gap, H = CGFloat(rows) * (tileH + label) + CGFloat(rows + 1) * gap
// Draw into an explicit sRGB bitmap (not the screen's colour space, which would embed the display profile).
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    .retagging(with: .sRGB)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.867, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
let font = NSFont(name: "Geneva", size: 13) ?? .systemFont(ofSize: 13)
for (i, it) in items.enumerated() {
    let c = i % cols, r = i / cols
    let x = gap + CGFloat(c) * (tileW + gap), yTop = H - gap - CGFloat(r) * (tileH + label + gap)
    let frame = NSRect(x: x, y: yTop - label - tileH, width: tileW, height: tileH + label)
    // platinum bevel
    NSColor.white.setFill(); NSRect(x: frame.minX - 1, y: frame.minY - 1, width: frame.width + 2, height: frame.height + 2).fill()
    NSColor(white: 0.6, alpha: 1).setFill(); NSRect(x: frame.minX, y: frame.minY - 1, width: frame.width + 1, height: frame.height + 1).fill()
    NSColor.black.setFill(); frame.fill()
    it.1.draw(in: NSRect(x: frame.minX + 1, y: frame.minY + 1, width: tileW - 2, height: tileH - 2))
    let bar = NSRect(x: frame.minX + 1, y: frame.maxY - label, width: tileW - 2, height: label - 1)
    NSColor(white: 0.867, alpha: 1).setFill(); bar.fill()
    (it.0 as NSString).draw(at: NSPoint(x: bar.minX + 6, y: bar.minY + 4), withAttributes: [.font: font, .foregroundColor: NSColor.black])
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
