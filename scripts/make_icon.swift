// Renders the Emulsion 98 app icon (a 35mm canister on a platinum tile) to a 1024px PNG.
// usage: swift scripts/make_icon.swift out.png
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // top-left origin

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

// Tile: platinum square with bevel and black outline (classic icon proportions).
let tile = rect(100, 100, 824, 824)
ctx.setFillColor(rgb(0, 0, 0, 0.35)); ctx.fill(tile.offsetBy(dx: 18, dy: 18))
ctx.setFillColor(rgb(0.867, 0.867, 0.867)); ctx.fill(tile)
ctx.setFillColor(rgb(1, 1, 1)); ctx.fill(rect(100, 100, 824, 16)); ctx.fill(rect(100, 100, 16, 824))
ctx.setFillColor(rgb(0.6, 0.6, 0.6)); ctx.fill(rect(100, 908, 824, 16)); ctx.fill(rect(908, 100, 16, 824))
ctx.setStrokeColor(rgb(0, 0, 0)); ctx.setLineWidth(8); ctx.stroke(tile)

// Pinstripes across the top like a window title bar.
for y in stride(from: 140.0, to: 220, by: 16) {
    ctx.setFillColor(rgb(0.6, 0.6, 0.6)); ctx.fill(rect(140, y, 744, 6))
    ctx.setFillColor(rgb(1, 1, 1)); ctx.fill(rect(140, y + 6, 744, 4))
}

// Film leader with sprocket holes.
let leader = CGMutablePath()
leader.move(to: CGPoint(x: 560, y: 380)); leader.addLine(to: CGPoint(x: 860, y: 380))
leader.addLine(to: CGPoint(x: 860, y: 600)); leader.addQuadCurve(to: CGPoint(x: 720, y: 720), control: CGPoint(x: 860, y: 720))
leader.addLine(to: CGPoint(x: 560, y: 720)); leader.closeSubpath()
ctx.addPath(leader); ctx.setFillColor(rgb(0.42, 0.25, 0.12)); ctx.fillPath()
ctx.addPath(leader); ctx.setStrokeColor(rgb(0, 0, 0)); ctx.setLineWidth(10); ctx.strokePath()
for i in 0..<4 { ctx.setFillColor(rgb(0.1, 0.06, 0.03)); ctx.fill(rect(600 + Double(i) * 64, 400, 34, 30)) }
for i in 0..<4 { ctx.setFillColor(rgb(0.1, 0.06, 0.03)); ctx.fill(rect(600 + Double(i) * 64, 660, 34, 30)) }

// Canister body.
let body = rect(250, 300, 340, 520)
ctx.setFillColor(rgb(0.98, 0.73, 0.08)); ctx.fill(body)
ctx.setFillColor(rgb(0.85, 0.2, 0.1)); ctx.fill(rect(250, 500, 340, 120))
ctx.setFillColor(rgb(1, 1, 1, 0.5)); ctx.fill(rect(275, 320, 30, 480))
ctx.setFillColor(rgb(0, 0, 0, 0.18)); ctx.fill(rect(530, 300, 60, 520))
ctx.setStrokeColor(rgb(0, 0, 0)); ctx.setLineWidth(10); ctx.stroke(body)
// Caps and spool.
for y in [250.0, 820.0] {
    ctx.setFillColor(rgb(0.25, 0.25, 0.25)); ctx.fill(rect(235, y, 370, 54))
    ctx.setStrokeColor(rgb(0, 0, 0)); ctx.stroke(rect(235, y, 370, 54))
}
ctx.setFillColor(rgb(0.3, 0.3, 0.3)); ctx.fill(rect(370, 196, 100, 54)); ctx.stroke(rect(370, 196, 100, 54))

// "98" label.
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
let font = NSFont(name: "Geneva", size: 150).map { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) } ?? NSFont.boldSystemFont(ofSize: 150)
("98" as NSString).draw(at: NSPoint(x: 330, y: 480), withAttributes: [.font: font, .foregroundColor: NSColor.white])

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
