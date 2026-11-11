import Foundation
import simd

// MARK: - Film handling: dust, hair, scratches, light leaks
//
// Each defect is injected at the stage where it physically happens, so its look follows from the process
// rather than being painted on:
//
// - **Dust and hair** sit on the processed film and block the light that passes through it. On a print
//   from a negative, that light would have exposed the paper, so dust prints *white*; on a slide it is
//   seen directly, so it shows *dark*; on a scanned negative the inversion makes it white again. A
//   diffusion enlarger's light wraps around small particles and partly fills their shadows, which is why
//   printers with dusty negatives preferred diffusion heads; a condenser shows every speck sharply.
// - **Emulsion scratches** remove dye. A shallow scratch takes only the top (blue-sensitive, yellow-dye)
//   layer, so on a colour print it shows as a coloured line; a deep one reaches the base and prints black
//   on a negative print (clear film passes all the light) and white on a slide.
// - **Base scratches** scatter light out of the enlarger's beam: they print as faint white lines under a
//   condenser and nearly vanish under diffusion light.
// - **Light leaks** enter through the camera back, so the light crosses the base and antihalation layer and
//   reaches the red-sensitive layer first (the redscale light path), which is why leaks are red-orange.
//
// Positions are in film-plane millimetres, so a defect lands in the same place in previews, crops and
// full-resolution exports.

/// Where the developed film is looked at through: sets how hard dust shadows are.
enum DustLight {
    case condenser, diffusion, scanner, viewing
    /// (opacity scale for dust, opacity scale for base scratches, shadow blur σ in µm)
    var params: (dust: Float, base: Float, blurUm: Float) {
        switch self {
        case .condenser: (1.0, 0.6, 4)
        case .diffusion: (0.6, 0.15, 10)
        case .scanner: (0.75, 0.3, 6)
        case .viewing: (1.0, 0.4, 5)
        }
    }
}

struct FrameGeometry {
    let w: Int, h: Int, originX: Int, originY: Int
    let full: SIMD2<Int>
    let mmPerPx: Float
    var frameMM: SIMD2<Float> { SIMD2(Float(full.x), Float(full.y)) * mmPerPx }
    var horizontal: Bool { full.x >= full.y }

    init(w: Int, h: Int, pixelUm: Float, context: DevelopContext) {
        self.w = w; self.h = h; originX = context.originX; originY = context.originY
        full = context.fullSize ?? SIMD2(w, h)
        mmPerPx = pixelUm / 1000
    }
    /// Film-plane mm -> buffer pixel coordinates.
    @inline(__always) func px(_ p: SIMD2<Float>) -> SIMD2<Float> {
        p / mmPerPx - SIMD2(Float(originX), Float(originY))
    }
}

enum Handling {
    struct Defects {
        /// Dust / hair / base-scratch light transmission at the negative (1 = clear), or nil.
        var transmission: [Float]?
        /// Emulsion-scratch depth in layers (0 = none; 1 = top layer gone; ≥ 2.2 = down to the base), or nil.
        var scratchDepth: [Float]?
    }

    static func defects(_ g: FrameGeometry, dust: Float, scratches: Float, seed: UInt32, light: DustLight) -> Defects {
        var out = Defects()
        let area = g.frameMM.x * g.frameMM.y / (36 * 24)
        let p = light.params
        var T: [Float]? = nil
        func opaque(_ i: Int, _ a: Float) {
            if T == nil { T = [Float](repeating: 1, count: g.w * g.h) }
            T![i] *= 1 - min(max(a, 0), 1)
        }
        // Dust specks and hairs.
        if dust > 0.005 {
            var rng = SplitMix(seed: UInt64(seed) &* 0x2545F4914F6CDD1D &+ 0xD057)
            let specks = Int((pow(dust, 1.4) * 260 * area).rounded())
            for _ in 0..<specks {
                let c = SIMD2(rng.unit(), rng.unit()) * g.frameMM
                let rUm = 3 * pow(20, pow(rng.unit(), 3))           // 3–60 µm, mostly small
                let op = (0.7 + 0.3 * rng.unit()) * p.dust
                disk(g, center: c, radiusMM: rUm / 1000, opacity: op, opaque)
            }
            let hairs = Int((pow(dust, 1.2) * 3 * area + rng.unit() * dust).rounded())
            for _ in 0..<hairs {
                var pt = SIMD2(rng.unit(), rng.unit()) * g.frameMM
                var ang = rng.unit() * 2 * .pi
                let len = 1 + 5 * rng.unit(), wUm = 12 + 25 * rng.unit()
                let steps = 24
                var pts = [pt]
                for _ in 0..<steps {
                    ang += (rng.unit() - 0.5) * 0.6
                    pt += SIMD2(cos(ang), sin(ang)) * (len / Float(steps))
                    pts.append(pt)
                }
                polyline(g, pts, halfWidthMM: wUm / 2000, opacity: 0.9 * p.dust, opaque)
            }
        }
        // Scratches along the film's length (the transport direction: the frame's long side).
        var D: [Float]? = nil
        if scratches > 0.005 {
            var rng = SplitMix(seed: UInt64(seed) &* 0x9E3779B97F4A7C15 &+ 0x5C7A)
            let n = Int((scratches * 4 + rng.unit() * scratches).rounded())
            for _ in 0..<max(n, 1) {
                let across = rng.unit()
                let wUm = 4 + 16 * rng.unit()
                let emulsion = rng.unit() < 0.6
                let depth = 0.4 + 2.2 * pow(rng.unit(), 1.5)
                let start = rng.unit() < 0.5 ? 0 : rng.unit() * 0.6, end = rng.unit() < 0.5 ? 1 : 0.4 + rng.unit() * 0.6
                let wobbleA = (0.05 + 0.3 * rng.unit()), wobbleF = 0.5 + 2 * rng.unit(), ph = rng.unit() * 6.28
                let longMM = g.horizontal ? g.frameMM.x : g.frameMM.y, shortMM = g.horizontal ? g.frameMM.y : g.frameMM.x
                var pts: [SIMD2<Float>] = []
                for k in 0...60 {
                    let t = start + (end - start) * Float(k) / 60
                    let a = across * shortMM + wobbleA * sin(wobbleF * t * 6.28 + ph)
                    pts.append(g.horizontal ? SIMD2(t * longMM, a) : SIMD2(a, t * longMM))
                }
                if emulsion {
                    polyline(g, pts, halfWidthMM: wUm / 2000, opacity: 1) { i, a in
                        if D == nil { D = [Float](repeating: 0, count: g.w * g.h) }
                        D![i] = max(D![i], depth * a)
                    }
                } else {
                    polyline(g, pts, halfWidthMM: wUm / 2000, opacity: 0.5 * p.base, opaque)
                }
            }
        }
        // Shadows of dust on the film are softened by defocus and by the light's spread.
        if var t = T {
            let s = p.blurUm / 1000 / g.mmPerPx
            if s > 0.3 {
                var o = t.map { 1 - $0 }
                o = Blur.gaussian(o, g.w, g.h, sigma: s)
                t = o.map { 1 - $0 }
            }
            out.transmission = t
        }
        out.scratchDepth = D
        return out
    }

    /// Light-leak exposure map (relative to the mid-grey exposure), or nil.
    static func lightLeak(_ g: FrameGeometry, amount: Float, seed: UInt32) -> [Float]? {
        guard amount > 0.005 else { return nil }
        var rng = SplitMix(seed: UInt64(seed) &* 0xBF58476D1CE4E5B9 &+ 0x1EAC)
        let F = g.frameMM
        // Which edge: leaks come mostly through the back door's long seals (top / bottom of the frame) and
        // the take-up end.
        let edge = Int(rng.unit() * 4)
        let along = rng.unit()
        let reach = (3 + 7 * rng.unit()) * (0.6 + 0.4 * amount)      // mm into the frame
        let spread = (6 + 12 * rng.unit())                              // mm along the edge
        let peak = amount * (4 + 6 * rng.unit())                       // × mid-grey exposure
        let lumps = (0..<2).map { _ in (rng.unit() * 6.28, 0.4 + 0.8 * rng.unit()) }
        var L = [Float](repeating: 0, count: g.w * g.h)
        L.withUnsafeMutableBufferPointer { lp in
            let P = lp.baseAddress!
            Parallel.rows(g.h) { rows in
                for y in rows {
                    for x in 0..<g.w {
                        let mm = (SIMD2(Float(x + g.originX), Float(y + g.originY)) + 0.5) * g.mmPerPx
                        let (d, a, len): (Float, Float, Float) = switch edge {
                        case 0: (mm.y, mm.x, F.x)
                        case 1: (F.y - mm.y, mm.x, F.x)
                        case 2: (mm.x, mm.y, F.y)
                        default: (F.x - mm.x, mm.y, F.y)
                        }
                        let u = (a - along * len) / spread
                        var lump: Float = 1
                        for (ph, f) in lumps { lump += 0.18 * sin(f * u * 2 + ph) }
                        // the leak's tongue reaches further in at its centre
                        let dd = max(d, 0) / (1 + 0.8 * exp(-0.5 * u * u))
                        P[y * g.w + x] = peak * exp(-dd / reach) * exp(-0.5 * u * u) * max(lump, 0.3)
                    }
                }
            }
        }
        return L
    }

    // MARK: Rasterising

    private static func disk(_ g: FrameGeometry, center: SIMD2<Float>, radiusMM: Float, opacity: Float, _ put: (Int, Float) -> Void) {
        let c = g.px(center)
        let r = radiusMM / g.mmPerPx
        let re = max(r, 0.5), op = opacity * min(1, (r / 0.5) * (r / 0.5))
        let x0 = max(Int(c.x - re - 1), 0), x1 = min(Int(c.x + re + 1), g.w - 1)
        let y0 = max(Int(c.y - re - 1), 0), y1 = min(Int(c.y + re + 1), g.h - 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 { for x in x0...x1 {
            let d = simd_length(SIMD2(Float(x) + 0.5, Float(y) + 0.5) - c) - re
            let cov = min(max(0.5 - d, 0), 1)
            if cov > 0 { put(y * g.w + x, op * cov) }
        } }
    }

    private static func polyline(_ g: FrameGeometry, _ pts: [SIMD2<Float>], halfWidthMM: Float, opacity: Float, _ put: (Int, Float) -> Void) {
        let hw0 = halfWidthMM / g.mmPerPx
        let hw = max(hw0, 0.5), op = opacity * min(1, hw0 / 0.5)
        var best = [Int: Float]()
        for (a0, b0) in zip(pts, pts.dropFirst()) {
            let a = g.px(a0), b = g.px(b0)
            let x0 = max(Int(min(a.x, b.x) - hw - 1), 0), x1 = min(Int(max(a.x, b.x) + hw + 1), g.w - 1)
            let y0 = max(Int(min(a.y, b.y) - hw - 1), 0), y1 = min(Int(max(a.y, b.y) + hw + 1), g.h - 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            let ab = b - a, l2 = max(simd_length_squared(ab), 1e-6)
            for y in y0...y1 { for x in x0...x1 {
                let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                let t = min(max(simd_dot(p - a, ab) / l2, 0), 1)
                let d = simd_length(p - (a + ab * t)) - hw
                let cov = min(max(0.5 - d, 0), 1)
                if cov > 0 { let i = y * g.w + x; best[i] = max(best[i] ?? 0, cov) }
            } }
        }
        for (i, c) in best { put(i, op * c) }
    }
}
