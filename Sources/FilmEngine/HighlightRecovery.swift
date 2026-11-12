import Foundation
import simd

// MARK: - Clipped highlight recovery
//
// A digital file stops at its clipping point; film keeps recording for several stops beyond it. Where a
// camera clipped, the film simulation would otherwise see a flat plateau: no shoulder, too little halation
// around the sun or a lamp, and wrong colour where only one or two channels clipped (the yellow / cyan
// sky). Recovery runs once on the whole loaded photo, so previews, crops and exports agree:
//
// 1. **Detection:** a channel is clipped where it sits on a plateau at its maximum (a camera JPEG, or a
//    raw beyond the sensor's range). Scene-linear HDR files have no plateau and are left alone.
// 2. **Colour (partially clipped pixels):** the clipped channels are rebuilt from the chromaticity of the
//    nearby unclipped surroundings (normalised convolution), scaled to the channels that survived.
// 3. **Magnitude (fully clipped regions):** the brightness grows smoothly from the region's edge into its
//    interior, by up to `maxStops`, as the least-curvature continuation of a bright source: a sun's core
//    is far brighter than its rim. The values are an estimate; their purpose is to give the film's shoulder
//    and halation realistic light to work with.
public enum HighlightRecovery {
    static let maxStops: Float = 4
    /// Dome scale as a fraction of the long side.
    static let domeScale: Float = 0.004

    /// Per-channel clip level (sRGB-linear) if the image has a clipped plateau.
    static func clipLevels(_ s: [[Float]]) -> SIMD3<Float>? {
        var out = SIMD3<Float>(repeating: .infinity)
        var any = false
        for c in 0..<3 {
            let v = s[c], n = v.count
            guard let mx = v.max(), mx > 0 else { continue }
            // Histogram of the top stop in 0.01-stop bins; a plateau is a tall bin near the top.
            let bins = 100
            var hist = [Int](repeating: 0, count: bins + 1)
            let lmx = log2(mx)
            for x in v where x > mx / 2 {
                let b = Int(((lmx - log2(x)) * 100).rounded())
                if b >= 0 && b <= bins { hist[b] += 1 }
            }
            guard let best = hist.indices.max(by: { hist[$0] < hist[$1] }) else { continue }
            // plateau: at least 0.03 % of the pixels in one 0.01-stop bin, and the bin near the top
            if Float(hist[best]) >= 0.0003 * Float(n) && best <= 30 {
                out[c] = mx * pow(2, -Float(best) / 100) * 0.993
                any = true
            }
        }
        return any ? out : nil
    }

    /// Recovers clipped highlights in a scene-linear Rec.2020 image. Returns true if anything was clipped.
    @discardableResult
    public static func recover(_ img: inout RGBImage) -> Bool {
        let w = img.width, h = img.height, n = w * h
        guard n > 16 else { return false }
        let to = Spectral.rec2020ToSRGB, back = Spectral.xyzToRec2020.compose(Spectral.srgbToXYZ)
        var s: [[Float]] = [[Float](repeating: 0, count: n), [Float](repeating: 0, count: n), [Float](repeating: 0, count: n)]
        for i in 0..<n {
            let v = to.apply(SIMD3(img.r[i], img.g[i], img.b[i]))
            s[0][i] = v.x; s[1][i] = v.y; s[2][i] = v.z
        }
        guard let clip = clipLevels(s) else { return false }
        var mask = [UInt8](repeating: 0, count: n)        // bit c: channel c clipped
        var clipped = 0
        for i in 0..<n {
            var m: UInt8 = 0
            for c in 0..<3 where s[c][i] >= clip[c] { m |= 1 << c }
            mask[i] = m
            if m != 0 { clipped += 1 }
        }
        guard clipped > 0 else { return false }

        // 2. Chromaticity of the unclipped surroundings (normalised convolution).
        let sigma = max(Float(max(w, h)) * 0.012, 2)
        var wgt = [Float](repeating: 0, count: n)
        var q: [[Float]] = [[Float](repeating: 0, count: n), [Float](repeating: 0, count: n), [Float](repeating: 0, count: n)]
        for i in 0..<n where mask[i] == 0 {
            let sum = max(s[0][i] + s[1][i] + s[2][i], 1e-6)
            // weight toward bright neighbours: they share the light source's colour
            let wi = min(sum, 3)
            wgt[i] = wi
            for c in 0..<3 { q[c][i] = max(s[c][i], 0) / sum * wi }
        }
        let wb = Blur.gaussian(wgt, w, h, sigma: sigma)
        let qb = (0..<3).map { Blur.gaussian(q[$0], w, h, sigma: sigma) }
        for i in 0..<n where mask[i] != 0 && mask[i] != 7 {
            guard wb[i] > 1e-5 else { continue }
            let chroma = SIMD3(qb[0][i], qb[1][i], qb[2][i]) / wb[i]
            // scale from the channels that did not clip
            var known: Float = 0, kq: Float = 0
            for c in 0..<3 where mask[i] & (1 << c) == 0 { known += s[c][i]; kq += chroma[c] }
            guard kq > 1e-4 else { continue }
            let k = known / kq
            for c in 0..<3 where mask[i] & (1 << c) != 0 { s[c][i] = min(max(s[c][i], k * chroma[c]), s[c][i] * 8) }
        }

        // 3. Fully clipped regions: brightness dome from the edge inward (chamfer distance transform).
        var d = [Float](repeating: 0, count: n)
        let inf: Float = 1e9
        for i in 0..<n { d[i] = mask[i] == 7 ? inf : 0 }
        let a: Float = 1, b: Float = 1.4142
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            guard d[i] > 0 else { continue }
            var m = d[i]
            if x > 0 { m = min(m, d[i - 1] + a) }
            if y > 0 { m = min(m, d[i - w] + a); if x > 0 { m = min(m, d[i - w - 1] + b) }; if x < w - 1 { m = min(m, d[i - w + 1] + b) } }
            d[i] = m
        } }
        for y in stride(from: h - 1, through: 0, by: -1) { for x in stride(from: w - 1, through: 0, by: -1) {
            let i = y * w + x
            guard d[i] > 0 else { continue }
            var m = d[i]
            if x < w - 1 { m = min(m, d[i + 1] + a) }
            if y < h - 1 { m = min(m, d[i + w] + a); if x < w - 1 { m = min(m, d[i + w + 1] + b) }; if x > 0 { m = min(m, d[i + w - 1] + b) } }
            d[i] = m
        } }
        let L = max(Float(max(w, h)) * domeScale, 1)
        for i in 0..<n where mask[i] == 7 {
            let stops = min(maxStops, 1.5 * (max(d[i] - 1, 0) / L).squareRoot())   // 0 at the edge: continuous
            // A fully clipped source keeps a little of its surroundings' hue (a sun is warm white).
            var chroma = SIMD3<Float>(repeating: 1 / 3)
            if wb[i] > 1e-5 { chroma = 0.5 * chroma + 0.5 * SIMD3(qb[0][i], qb[1][i], qb[2][i]) / wb[i] }
            let base = SIMD3(s[0][i], s[1][i], s[2][i])
            let lum = base.max()
            let v = chroma / max(chroma.max(), 1e-6) * lum * pow(2, stops)
            s[0][i] = max(base.x, v.x); s[1][i] = max(base.y, v.y); s[2][i] = max(base.z, v.z)
        }
        for i in 0..<n where mask[i] != 0 {
            let v = back.apply(SIMD3(s[0][i], s[1][i], s[2][i]))
            img.r[i] = v.x; img.g[i] = v.y; img.b[i] = v.z
        }
        return true
    }
}

extension FilmDiagnostics {
    /// Synthetic HDR scene (sky, a sun 6 stops over the clip point, an orange lamp clipping in red only),
    /// developed from the true values, the clipped values and the recovered values.
    public static func highlightReport(_ stock: FilmStock) -> String {
        let w = 1800, h = 1200, n = w * h
        var truth = RGBImage(width: w, height: h)
        let toRec = Spectral.xyzToRec2020.compose(Spectral.srgbToXYZ)
        let sun = SIMD2<Float>(1080, 420), lamp = SIMD2<Float>(450, 760)
        for y in 0..<h { for x in 0..<w {
            let p = SIMD2(Float(x), Float(y))
            let t = Float(y) / Float(h)
            var c = SIMD3<Float>(0.55, 0.42, 0.30) * (1 - 0.6 * t) + SIMD3<Float>(0.05, 0.05, 0.06) * t   // warm sky to dark ground
            let ds = simd_length(p - sun), dl = simd_length(p - lamp)
            c += SIMD3<Float>(1, 0.92, 0.75) * (64 * exp(-0.5 * (ds / 18) * (ds / 18)) + 3 * exp(-ds / 90))   // sun + glow
            c += SIMD3<Float>(1, 0.5, 0.15) * (5 * exp(-0.5 * (dl / 14) * (dl / 14)))                       // orange lamp
            let r = toRec.apply(c)
            truth.r[y * w + x] = r.x; truth.g[y * w + x] = r.y; truth.b[y * w + x] = r.z
        } }
        var clipped = truth
        let toS = Spectral.rec2020ToSRGB
        for i in 0..<n {
            let v = simd_min(toS.apply(SIMD3(truth.r[i], truth.g[i], truth.b[i])), SIMD3(repeating: 1))
            let r = toRec.apply(v)
            clipped.r[i] = r.x; clipped.g[i] = r.y; clipped.b[i] = r.z
        }
        var recovered = clipped
        let did = HighlightRecovery.recover(&recovered)
        var settings = DevelopSettings(); settings.grain = 0; settings.sceneLight = false; settings.enlargerFalloff = false
        let ctx = DevelopContext(fullLongSide: w)
        let a = Developer.develop(truth, stock: stock, settings: settings, context: ctx)
        let b = Developer.develop(clipped, stock: stock, settings: settings, context: ctx)
        let c = Developer.develop(recovered, stock: stock, settings: settings, context: ctx)
        func err(_ o: RGBImage, near pt: SIMD2<Float>, r0: Float, r1: Float) -> Float {
            var e: Float = 0, k: Float = 0
            for y in stride(from: 0, to: h, by: 2) { for x in stride(from: 0, to: w, by: 2) {
                let d = simd_length(SIMD2(Float(x), Float(y)) - pt)
                guard d >= r0 && d <= r1 else { continue }
                let i = y * w + x
                e += (abs(o.r[i] - a.r[i]) + abs(o.g[i] - a.g[i]) + abs(o.b[i] - a.b[i])) / 3 * 255; k += 1
            } }
            return e / max(k, 1)
        }
        var s = "\(stock.id): synthetic HDR scene, clipping \(did ? "detected" : "NOT detected")\n"
        s += "mean |error| vs the true-HDR render, 8-bit levels:   clipped   recovered\n"
        for (name, pt, r0, r1) in [("sun core", sun, Float(0), Float(20)), ("sun glow / halation", sun, Float(20), Float(120)),
                                   ("lamp", lamp, Float(0), Float(16)), ("lamp surroundings", lamp, Float(16), Float(80))] {
            s += String(format: "  %-22@ %8.1f  %9.1f\n", name as NSString, err(b, near: pt, r0: r0, r1: r1), err(c, near: pt, r0: r0, r1: r1))
        }
        return s
    }
}
