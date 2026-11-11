import Foundation
import simd

// MARK: - The enlarger: light source, lens and easel

/// Enlarger light source.
public enum Enlarger: String, CaseIterable, Codable, Identifiable {
    /// Colour / variable-contrast head with a mixing box: diffuse light.
    case diffusion
    /// Condenser head: a lamp focused through condenser lenses, so the light through the negative is nearly
    /// collimated.
    case condenser
    public var id: String { rawValue }
    public var label: String { self == .diffusion ? "Diffusion (colour head)" : "Condenser" }

    /// Effective printing density of a silver negative (Callier effect).
    ///
    /// Silver grains scatter as well as absorb. Under diffuse light the scattered light still reaches the
    /// lens; under collimated condenser light much of it is lost, so the negative prints denser, and more so
    /// where there is more silver. The ratio of specular to diffuse density, Callier's Q, is about 1.3 for
    /// typical negatives at medium density and lower in thin shadows. A condenser print is therefore
    /// roughly a paper grade harder than a diffusion print, with crisper, more visible grain (grain clumps
    /// gain contrast too). Dye images barely scatter (Q ≈ 1), which is why colour heads lose nothing.
    @inline(__always) func printingDensity(_ d: Float) -> Float {
        guard self == .condenser else { return d }
        let dd = max(d, 0)
        return d + 0.28 * dd * (1 - exp(-dd / 0.4))
    }
}

enum EnlargerOptics {
    /// Enlarging-lens blur at the negative plane (σ): MTF 50 % near 45 lp/mm, a good 6-element lens at f/8,
    /// including the small focus error across the easel.
    static let lensBlurUm: Float = 4.5
    /// The lens's focal length is about the negative diagonal, and at typical enlargements (×5–×10) the
    /// negative sits about 1.12 focal lengths in front of it.
    static let objectDistance: Float = 1.125

    /// Lens blur and illumination falloff, applied to the paper's exposure (linear light) given as log10
    /// exposures per paper layer.
    ///
    /// Falloff: light reaching the paper corners passes the lens obliquely. The cos⁴θ law would give
    /// about 0.5 stop less exposure at a 35 mm frame's corners; enlarging lenses, designed for an even
    /// field, measure about 80–85 % of the centre's illumination there at f/8, so relative illumination is
    /// taken as cos²θ (0.84 at the corner, a quarter stop). On a negative-to-positive print that means
    /// *lighter* corners, the opposite of camera vignetting, and why printers routinely burned them in.
    static func apply(_ R: inout [Float], _ G: inout [Float], _ B: inout [Float], w: Int, h: Int, mono: Bool,
                      pixelUm: Float, format: FilmFormat, context: DevelopContext, falloff: Bool) {
        let n = w * h
        let blur = lensBlurUm / pixelUm
        guard blur > 0.3 || falloff else { return }
        let full = context.fullSize ?? SIMD2(w, h)
        let longPx = Float(max(full.x, full.y)), shortPx = Float(min(full.x, full.y))
        let longMM = format.longSideMM, shortMM = longMM * shortPx / max(longPx, 1)
        let diag = (longMM * longMM + shortMM * shortMM).squareRoot()
        let u = objectDistance * diag
        let mmPerPx = pixelUm / 1000
        let cx = Float(full.x) / 2, cy = Float(full.y) / 2
        func toLinear(_ v: inout [Float]) {
            v.withUnsafeMutableBufferPointer { vp in
                let V = vp.baseAddress!
                Parallel.rows(h) { rows in
                    for y in rows {
                        let dy = (Float(y + context.originY) + 0.5 - cy) * mmPerPx
                        for x in 0..<w {
                            let i = y * w + x
                            var e = pow(10, V[i])
                            if falloff {
                                let dx = (Float(x + context.originX) + 0.5 - cx) * mmPerPx
                                let t = (dx * dx + dy * dy) / (u * u)
                                e /= 1 + t                     // cos²θ with tan²θ = t
                            }
                            V[i] = e
                        }
                    }
                }
            }
            if blur > 0.3 { v = Blur.gaussian(v, w, h, sigma: blur) }
            for i in 0..<n { v[i] = log10(max(v[i], 1e-12)) }
        }
        toLinear(&R)
        if mono { G = R; B = R } else { toLinear(&G); toLinear(&B) }
    }
}
