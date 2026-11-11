import Foundation
import FilmEngine
import AppKit

// Developer test tool for the film engine.
//   emulsion-cli list
//   emulsion-cli develop <input> <stockID|all> <outDir> [--long N] [--format mm35|mf645|mf67] [--grain X] [--ev X]
//   emulsion-cli crop <input> <stockID> <out.jpg> [--size 600] [--cx 0.5 --cy 0.5]
//   emulsion-cli sheet <input> <out.jpg> [--long 480]
//   emulsion-cli chart <outDir>

var args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let longOpt = opt("--long").flatMap(Int.init)
let sizeOpt = opt("--size").flatMap(Int.init) ?? 600
let cx = opt("--cx").flatMap(Float.init) ?? 0.5
let cy = opt("--cy").flatMap(Float.init) ?? 0.5
var settings = DevelopSettings()
if let f = opt("--format"), let ff = FilmFormat(rawValue: f) { settings.format = ff }
if let g = opt("--grain").flatMap(Float.init) { settings.grain = g }
if let e = opt("--ev").flatMap(Float.init) { settings.exposure = e }
if let e = opt("--push").flatMap(Float.init) { settings.push = e }
if let e = opt("--lab").flatMap(Float.init) { settings.labCorrection = e }
if args.contains("--scan") { settings.lab = .scan; args.removeAll { $0 == "--scan" } }
if let a = opt("--agitation"), let v = Agitation(rawValue: a) { settings.agitation = v }
if let a = opt("--age").flatMap(Float.init) { settings.ageYears = a }
if let a = opt("--storage"), let v = Storage(rawValue: a) { settings.storage = v }
if let a = opt("--filter"), let v = LensFilter(rawValue: a) { settings.filter = v }
if args.contains("--xpro") { settings.crossProcess = true; args.removeAll { $0 == "--xpro" } }
if args.contains("--redscale") { settings.redscale = true; args.removeAll { $0 == "--redscale" } }
if let v = opt("--cc-y").flatMap(Float.init) { settings.ccYellow = v }
if let v = opt("--cc-m").flatMap(Float.init) { settings.ccMagenta = v }
if let v = opt("--print-ev").flatMap(Float.init) { settings.printExposure = v }
if let v = opt("--preflash").flatMap(Float.init) { settings.preflash = v }
if let v = opt("--grade").flatMap(Float.init) { settings.paperGrade = v }
if let v = opt("--border"), let b = FilmBorder(rawValue: v) { settings.border = b }
if let v = opt("--surface"), let b = PaperSurface(rawValue: v) { settings.paperSurface = b }
if let v = opt("--print-age").flatMap(Float.init) { settings.printAge = v }
if let v = opt("--keeping"), let k = Keeping(rawValue: v) { settings.keeping = k }
let kelvinOpt = opt("--kelvin").flatMap(Float.init)
let timeOpt = opt("--time").flatMap(Double.init)

func stocks(_ id: String) -> [FilmStock] {
    if id == "all" { return FilmStock.catalog }
    guard let s = FilmStock.stock(id: id) else { fail("unknown stock \(id)") }
    return [s]
}

func timeit<T>(_ label: String, _ f: () throws -> T) rethrows -> T {
    let t = Date(); let r = try f()
    print(String(format: "%@: %.0f ms", label, Date().timeIntervalSince(t) * 1000))
    return r
}

guard let cmd = args.first else { fail("usage: emulsion-cli list|develop|crop|sheet|chart …") }

switch cmd {
case "probe":
    // probe <stock> r g b
    let st = stocks(args[1])[0]
    let c = SIMD3<Float>(Float(args[2])!, Float(args[3])!, Float(args[4])!)
    for (k, lab) in [(nil, Float(0)), (Float(3000), Float(0)), (Float(3000), Float(0.7)), (Float(3000), Float(1))] as [(Float?, Float)] {
        let o = FilmDiagnostics.probe(st, srgb: c, kelvin: k, correction: lab)
        print(String(format: "%@ lab %.1f -> %3.0f %3.0f %3.0f", k.map { "\(Int($0))K" } ?? "neutral", lab, o.x, o.y, o.z))
    }

case "trace":
    print(FilmDiagnostics.trace(stocks(args[1])[0], srgb: SIMD3<Float>(Float(args[2])!, Float(args[3])!, Float(args[4])!)))

case "ramp":
    print(FilmDiagnostics.rampReport(stocks(args[1])[0], push: Float(args.count > 2 ? args[2] : "0") ?? 0))

case "technique":
    print(FilmDiagnostics.techniqueReport(stocks(args[1])[0], filter: settings.filter, redscale: settings.redscale))

case "fade":
    // fade <stock|all>: patch colours (8-bit sRGB in -> out) as the picture ages, for the chosen keeping.
    for st in stocks(args[1]) { print(FilmDiagnostics.fadeReport(st, settings: settings)) }

case "lut":
    // lut <stock|all> <outDir> [--size 33]
    guard args.count >= 3 else { fail("lut <stock|all> <outDir>") }
    let dir = URL(fileURLWithPath: args[2])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let n = sizeOpt == 600 ? 33 : sizeOpt
    for st in stocks(args[1]) {
        let text = timeit(st.id) { LUTExport.cube(stock: st, settings: settings, size: n) }
        try text.write(to: dir.appendingPathComponent(LUTExport.fileName(st)), atomically: true, encoding: .utf8)
    }

case "lutcheck":
    // lutcheck <image> <stock>: LUT applied to the image vs a full develop without grain/halation
    let photo = try PhotoIO.load(URL(fileURLWithPath: args[1]), maxLongSide: 900)
    let st = stocks(args[2])[0]
    var flat = settings; flat.grain = 0; flat.halation = 0
    let lut = LUTExport.cube(stock: st, settings: flat)
    var ctx = photo.context(seed: 1); ctx.isDisplayReferred = true
    let dev = Developer.develop(photo.image, stock: st, settings: flat, context: ctx)
    let orig = PhotoIO.displayOriginal(photo.image)
    var sum: Double = 0, mx: Float = 0
    for i in 0..<orig.r.count {
        let c = LUTExport.apply(lut, r: orig.r[i], g: orig.g[i], b: orig.b[i])
        let e = SIMD3<Float>(dev.r[i], dev.g[i], dev.b[i])
        let d = max(abs(c.x - e.x), abs(c.y - e.y), abs(c.z - e.z)) * 255
        sum += Double(d); mx = max(mx, d)
    }
    print(String(format: "%@: LUT vs full develop (no grain/halation): mean %.2f, max %.1f (8-bit levels)", st.id, sum / Double(orig.r.count), mx))

case "granularity":
    for st in stocks(args[1]) { print(FilmDiagnostics.granularity(st)) }

case "mtf":
    print(FilmDiagnostics.mtf(stocks(args[1])[0]))

case "gamut":
    print(FilmDiagnostics.gamutReport(stocks(args[1])[0]))

case "diag":
    print(FilmDiagnostics.hueReport(stocks(args[1])[0])); print(FilmDiagnostics.report(stocks(args[1])[0]))

case "list":
    for s in FilmStock.catalog {
        if args.contains("--long") { print(String(format: "%@\t%@\thalation R %.3f G %.3f\tgrain RMS %.1f", s.id, s.displayName, s.halationRGB.x, s.halationRGB.y, s.grainRMS)) }
        else { print("\(s.id)\t\(s.displayName)\t\(s.kind.rawValue)") }
    }

case "develop":
    guard args.count >= 4 else { fail("develop <input> <stock|all> <outDir>") }
    let input = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[3])
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let photo = try timeit("load") { try PhotoIO.load(input, maxLongSide: longOpt) }
    print("size \(photo.image.width)x\(photo.image.height) full \(photo.fullLongSide) displayReferred \(photo.isDisplayReferred)")
    print("camera \(photo.capture.cameraName) [\(photo.capture.profileName)] \(photo.capture.exposureSummary) WB \(photo.capture.asShotKelvin.map { "\(Int($0))K" } ?? "n/a")")
    for s in stocks(args[2]) {
        var ctx = photo.context(seed: PhotoIO.seed(for: input))
        if let k = kelvinOpt { ctx.sceneKelvin = k }
        if let t = timeOpt { ctx.exposureTime = t }
        var out = timeit(s.id) { Developer.develop(photo.image, stock: s, settings: settings, context: ctx) }
        out = Border.apply(out, style: settings.border, format: settings.format, stock: s, seed: ctx.seed)
        try PhotoIO.save(out, to: outDir.appendingPathComponent("\(s.id).jpg"), format: .jpeg, source: input, stockName: s.displayName)
    }

case "crop":
    guard args.count >= 4 else { fail("crop <input> <stock> <out>") }
    let input = URL(fileURLWithPath: args[1])
    let photo = try PhotoIO.load(input)
    let img = photo.image
    let x = Int(Float(img.width) * cx) - sizeOpt / 2, y = Int(Float(img.height) * cy) - sizeOpt / 2
    let crop = img.cropped(x: x, y: y, width: sizeOpt, height: sizeOpt)
    let s = stocks(args[2])[0]
    var ctx = photo.context(fullLongSide: img.longSide, originX: x, originY: y, seed: PhotoIO.seed(for: input))
    if let k = kelvinOpt { ctx.sceneKelvin = k }
    if let t = timeOpt { ctx.exposureTime = t }
    let out = Developer.develop(crop, stock: s, settings: settings, context: ctx)
    try PhotoIO.save(out, to: URL(fileURLWithPath: args[3]), format: .jpeg, source: nil, stockName: s.displayName)

case "sheet", "chart":
    let isChart = cmd == "chart"
    guard args.count >= 3 || (isChart && args.count >= 2) else { fail("sheet <input> <out.jpg>") }
    var base: RGBImage
    var displayRef = true
    var seedURL = URL(fileURLWithPath: "chart")
    if isChart {
        // Grey ramp (−5…+5 stops) over a row of saturated patches.
        let w = 660, h = 300
        base = RGBImage(width: w, height: h)
        let patches: [SIMD3<Float>] = [[0.45, 0.05, 0.04], [0.6, 0.25, 0.08], [0.55, 0.5, 0.05], [0.08, 0.35, 0.07],
                                       [0.05, 0.35, 0.45], [0.04, 0.08, 0.5], [0.4, 0.06, 0.35], [0.45, 0.28, 0.2],
                                       [0.13, 0.20, 0.42], [0.20, 0.30, 0.08], [0.6, 0.6, 0.6], [0.03, 0.03, 0.03]]
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if y < 150 {
                    let stop = Float(x / 60) - 5
                    let v = 0.18 * pow(2, stop)
                    base.r[i] = v; base.g[i] = v; base.b[i] = v
                } else {
                    let p = patches[min(x / 55, 11)]
                    base.r[i] = p.x; base.g[i] = p.y; base.b[i] = p.z
                }
            }
        }
        // chart values are linear sRGB; the engine expects linear Rec.2020
        for i in 0..<base.r.count {
            let v = SIMD3<Float>(base.r[i], base.g[i], base.b[i])
            let xyz = SIMD3<Float>((SIMD3<Float>(0.4124564, 0.3575761, 0.1804375) * v).sum(),
                                   (SIMD3<Float>(0.2126729, 0.7151522, 0.0721750) * v).sum(),
                                   (SIMD3<Float>(0.0193339, 0.1191920, 0.9503041) * v).sum())
            base.r[i] = (SIMD3<Float>(1.7166512, -0.3556708, -0.2533663) * xyz).sum()
            base.g[i] = (SIMD3<Float>(-0.6666844, 1.6164812, 0.0157685) * xyz).sum()
            base.b[i] = (SIMD3<Float>(0.0176399, -0.0427706, 0.9421031) * xyz).sum()
        }
        displayRef = false
    } else {
        let input = URL(fileURLWithPath: args[1])
        let photo = try PhotoIO.load(input, maxLongSide: longOpt ?? 480)
        base = photo.image; displayRef = photo.isDisplayReferred; seedURL = input
    }
    let outURL = URL(fileURLWithPath: isChart ? args[1] + "/chart_sheet.jpg" : args[2])
    if isChart { try FileManager.default.createDirectory(atPath: args[1], withIntermediateDirectories: true) }

    let all = [nil] + FilmStock.catalog.map { Optional($0) }
    let cols = 4, tw = base.width, th = base.height, label = 22
    let rows = (all.count + cols - 1) / cols
    let W = cols * tw, H = rows * (th + label)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(gray: 0.1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    for (k, s) in all.enumerated() {
        let dc = DevelopContext(fullLongSide: base.longSide, seed: PhotoIO.seed(for: seedURL), isDisplayReferred: displayRef,
                                sceneKelvin: kelvinOpt)
            .with { $0.exposureTime = timeOpt }
        let img: RGBImage
        if let s { img = Developer.develop(base, stock: s, settings: settings, context: dc) }
        else { img = PhotoIO.displayOriginal(base) }
        if isChart, let s {
            // Print grey-ramp values: should be neutral at mid grey.
            let y = 75, line = (0..<11).map { stop -> String in
                let i = y * img.width + stop * 60 + 30
                return String(format: "%3.0f/%3.0f/%3.0f", img.r[i] * 255, img.g[i] * 255, img.b[i] * 255)
            }
            print(s.id.padding(toLength: 14, withPad: " ", startingAt: 0), line[0], line[3], line[5], line[7], line[10])
        }
        let col = k % cols, row = k / cols
        let y0 = H - (row + 1) * (th + label)
        if let cg = PhotoIO.cgImage(img) { ctx.draw(cg, in: CGRect(x: col * tw, y: y0, width: tw, height: th)) }
        let name = s?.displayName ?? "Original"
        (name as NSString).draw(at: NSPoint(x: col * tw + 6, y: y0 + th + 4),
                                withAttributes: [.font: NSFont(name: "Geneva", size: 13) ?? NSFont.systemFont(ofSize: 13),
                                                 .foregroundColor: NSColor.white])
    }
    let sheet = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, sheet, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    CGImageDestinationFinalize(dest)
    print("wrote \(outURL.path)")

default:
    fail("unknown command \(cmd)")
}
