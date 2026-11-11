import Foundation
import CoreGraphics
import CoreText

/// Frame borders, drawn as the film would print or scan them.
///
/// - Filed carrier: a negative carrier filed out past the frame prints the film's clear rebate — which
///   on a negative prints maximum black — with the rough edge of the filing, inside a white paper margin.
/// - Full-frame scan: the whole strip. The unexposed rebate inverts to black on negatives (it is clear
///   film) and is black on slides (D-max); sprocket holes pass all the scanner's light; the manufacturer's
///   latent-image edge print (stock name, frame numbers) is pre-exposed, so it develops and shows light.
public enum Border {
    public static func apply(_ img: RGBImage, style: FilmBorder, format: FilmFormat, stock: FilmStock, seed: UInt32) -> RGBImage {
        guard style != .none else { return img }
        let w = img.width, h = img.height
        let long = CGFloat(max(w, h)), short = CGFloat(min(w, h))
        let landscape = w >= h
        var rng = SplitMix(seed: UInt64(seed) &+ 0x9E37)
        // canvas geometry (in image pixels)
        let pxPerMM = long / CGFloat(format.longSideMM)
        let rebate: CGFloat, margin: CGFloat
        switch style {
        case .filed: rebate = 1.2 * pxPerMM; margin = 0.05 * long
        case .fullFrame: rebate = (format.hasSprockets ? 5.6 : 4.0) * pxPerMM * (format == .halfFrame ? 1.5 : 1); margin = 0
        case .none: rebate = 0; margin = 0
        }
        let side = style == .fullFrame ? 1.6 * pxPerMM : rebate   // gap between frames along the strip
        let cw = Int(CGFloat(w) + 2 * (margin + (landscape ? side : rebate))), ch = Int(CGFloat(h) + 2 * (margin + (landscape ? rebate : side)))
        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let photo = PhotoIO.cgImage(img) else { return img }
        let paper = CGColor(srgbRed: 0.965, green: 0.96, blue: 0.95, alpha: 1)
        let black = CGColor(srgbRed: 0.035, green: 0.033, blue: 0.03, alpha: 1)
        ctx.setFillColor(style == .filed ? paper : black)
        ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
        let frame = CGRect(x: margin + (landscape ? side : rebate), y: margin + (landscape ? rebate : side), width: CGFloat(w), height: CGFloat(h))

        switch style {
        case .filed:
            // rough, hand-filed edge: jitter the black outline outward by up to ~0.5 mm
            let outer = frame.insetBy(dx: -rebate, dy: -rebate)
            let path = CGMutablePath()
            let steps = 400
            // a wobbly filed edge: low-passed random offsets with the odd file mark, not a saw-tooth
            func edge() -> [CGFloat] {
                let raw = (0..<(steps + 16)).map { _ in CGFloat(rng.unit()) }
                return (0..<steps).map { i in
                    let avg = raw[i..<(i + 16)].reduce(0, +) / 16
                    let mark: CGFloat = rng.unit() < 0.012 ? CGFloat(rng.unit()) * 0.5 : 0
                    return (0.15 + 0.6 * avg + mark) * pxPerMM
                }
            }
            let e = (0..<4).map { _ in edge() }
            var pts: [CGPoint] = []
            for i in 0..<steps { let t = CGFloat(i) / CGFloat(steps); pts.append(CGPoint(x: outer.minX + t * outer.width, y: outer.minY - e[0][i])) }
            for i in 0..<steps { let t = CGFloat(i) / CGFloat(steps); pts.append(CGPoint(x: outer.maxX + e[1][i], y: outer.minY + t * outer.height)) }
            for i in 0..<steps { let t = CGFloat(i) / CGFloat(steps); pts.append(CGPoint(x: outer.maxX - t * outer.width, y: outer.maxY + e[2][i])) }
            for i in 0..<steps { let t = CGFloat(i) / CGFloat(steps); pts.append(CGPoint(x: outer.minX - e[3][i], y: outer.maxY - t * outer.height)) }
            path.addLines(between: pts); path.closeSubpath()
            ctx.setFillColor(black); ctx.addPath(path); ctx.fillPath()
            ctx.draw(photo, in: frame)
        case .fullFrame:
            ctx.draw(photo, in: frame)
            let slide = stock.kind == .slide
            let hole = slide ? CGColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1) : CGColor(srgbRed: 0.10, green: 0.095, blue: 0.09, alpha: 1)
            let ink = stock.kind == .colorNegative ? CGColor(srgbRed: 0.93, green: 0.80, blue: 0.48, alpha: 1)
                                                   : CGColor(srgbRed: 0.88, green: 0.88, blue: 0.86, alpha: 1)
            // the strip runs along the long side; rebates are the bands outside the short side
            let along = landscape ? CGFloat(cw) : CGFloat(ch)
            func band(_ top: Bool) -> CGRect {
                landscape ? CGRect(x: 0, y: top ? frame.maxY : 0, width: CGFloat(cw), height: rebate)
                          : CGRect(x: top ? frame.maxX : 0, y: 0, width: rebate, height: CGFloat(ch))
            }
            if format.hasSprockets {
                // ISO 35 mm perforations: 2.8 × 1.98 mm, pitch 4.75 mm
                let pw = 1.98 * pxPerMM, ph = 2.8 * pxPerMM, pitch = 4.75 * pxPerMM
                ctx.setFillColor(hole)
                for top in [true, false] {
                    let b = band(top)
                    var s = (along.truncatingRemainder(dividingBy: pitch)) / 2
                    while s + pw < along {
                        // perforations start 1 mm outside the frame; the edge print runs outside them
                        let off = 1.0 * pxPerMM
                        let r = landscape ? CGRect(x: s, y: top ? b.minY + off : b.maxY - off - ph, width: pw, height: ph)
                                          : CGRect(x: top ? b.minX + off : b.maxX - off - ph, y: s, width: ph, height: pw)
                        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 0.4 * pxPerMM, cornerHeight: 0.4 * pxPerMM, transform: nil)); ctx.fillPath()
                        s += pitch
                    }
                }
            }
            // edge print: stock name and frame numbers along the outer rebate
            let n = Int(seed % 34) + 2
            let text = "\(stock.maker.uppercased())  \(stock.name.uppercased())     \(n)   ▸ \(n)A     \(n + 1)"
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, (format.hasSprockets ? 1.05 : 1.4) * pxPerMM, nil)
            let attr = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink] as CFDictionary
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attr)!)
            ctx.saveGState()
            let b = band(true)
            if landscape {
                ctx.textPosition = CGPoint(x: frame.minX + 0.08 * frame.width, y: b.maxY - (format.hasSprockets ? 1.45 : 2.4) * pxPerMM)
            } else {
                ctx.translateBy(x: b.maxX - (format.hasSprockets ? 1.45 : 2.4) * pxPerMM, y: frame.minY + 0.08 * frame.height)
                ctx.rotate(by: .pi / 2)
                ctx.textPosition = .zero
            }
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        case .none: break
        }
        guard let data = ctx.data else { return img }
        let p = data.bindMemory(to: UInt8.self, capacity: cw * ch * 4)
        var out = RGBImage(width: cw, height: ch)
        for y in 0..<ch { for x in 0..<cw {
            let s = (y * cw + x) * 4, d = y * cw + x
            out.r[d] = Float(p[s]) / 255; out.g[d] = Float(p[s + 1]) / 255; out.b[d] = Float(p[s + 2]) / 255
        } }
        return out
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
}
