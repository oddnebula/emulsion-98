import Foundation
import simd

/// Grain statistics from the measured sub-emulsions.
///
/// Each colour layer of a modern film is coated as three sub-emulsions — fast, medium and slow — that
/// fill one after another as exposure rises (spektrafilm's `density_curves_layers`, fitted to the
/// datasheet). The fast one has large crystals and dominates the grain of thin areas; as it saturates,
/// the finer medium and slow emulsions take over. Granularity therefore depends on *which* sub-emulsion
/// carries the density, not just on the density itself.
///
/// Per sub-emulsion k, the density fluctuation follows the Nutting / Siedentopf relation for a binomial
/// fill plus dye-cloud placement: σ²ₖ = κ · aₖ · Dmaxₖ · [pₖ(1 − pₖ) + 0.05 pₖ] / A, with pₖ its filled fraction, aₖ its relative crystal
/// area and A the measuring area (pixel, or the dye cloud when the pixel is smaller). Relative crystal
/// areas come from the sub-emulsions' measured speed separation (area ∝ speed^½). κ is set per layer so
/// the total RMS granularity at D = 1 through a 48 µm aperture equals the datasheet figure.
struct GrainLayers {
    static let dStep: Float = 0.02
    /// [channel][density index] -> filled fraction of each sub-emulsion.
    let p: [[SIMD3<Float>]]
    /// [channel] -> sub-emulsion maximum densities and relative crystal areas (fastest = 1).
    let dmax: [SIMD3<Float>]
    let area: [SIMD3<Float>]

    init?(_ m: MeasuredProfile) {
        guard m.layerCurves.count == 3, m.layerCurves.allSatisfy({ $0.count == 3 }) else { return nil }
        var pp: [[SIMD3<Float>]] = [], dm: [SIMD3<Float>] = [], ar: [SIMD3<Float>] = []
        let x0 = MeasuredData.logExposureStart, dx = MeasuredData.logExposureStep
        for c in 0..<3 {
            let total = m.curves[c], subs = m.layerCurves[c]
            let mx = SIMD3((0..<3).map { k in max(subs[k].max() ?? 0, 1e-3) })
            // Speed of each sub-emulsion: log exposure where it is half way between empty and full.
            let increasing = (total.last ?? 0) > (total.first ?? 0)
            var half = SIMD3<Float>(repeating: 0)
            for k in 0..<3 {
                let target = 0.5 * mx[k]
                let i = subs[k].firstIndex { increasing ? $0 >= target : $0 <= target } ?? 0
                half[k] = x0 + Float(i) * dx
            }
            // Negative: fastest = lowest log E at half fill. Reversal: the dye left where the *first*
            // development did not act, so the fastest emulsion is still the one with the lowest log E.
            let fastest = half.min()
            let a = SIMD3((0..<3).map { k in pow(10, -0.5 * (half[k] - fastest)) })
            // Density -> fill fractions, from (total, sub-emulsions) pairs along the curve.
            var pairs: [(Float, SIMD3<Float>)] = []
            for i in 0..<total.count {
                let f = SIMD3((0..<3).map { k in min(max(subs[k][i] / mx[k], 0), 1) })
                pairs.append((total[i], f))
            }
            pairs.sort { $0.0 < $1.0 }
            let top = (pairs.last?.0 ?? 2) + 0.1
            var table: [SIMD3<Float>] = []
            var j = 0
            var d: Float = 0
            while d <= top {
                while j + 1 < pairs.count && pairs[j + 1].0 < d { j += 1 }
                if j + 1 < pairs.count, pairs[j + 1].0 > pairs[j].0 {
                    let t = min(max((d - pairs[j].0) / (pairs[j + 1].0 - pairs[j].0), 0), 1)
                    table.append(pairs[j].1 + (pairs[j + 1].1 - pairs[j].1) * t)
                } else {
                    table.append(pairs[min(j + 1, pairs.count - 1)].1)
                }
                d += Self.dStep
            }
            pp.append(table); dm.append(mx); ar.append(a)
        }
        p = pp; dmax = dm; area = ar
    }

    @inline(__always) func fill(_ c: Int, _ d: Float) -> SIMD3<Float> {
        let t = p[c]
        let f = max(d, 0) / Self.dStep
        let i = min(Int(f), t.count - 2), u = min(f - Float(i), 1)
        return t[i] + (t[i + 1] - t[i]) * u
    }

    /// Positional noise of the dye clouds, which remains once a sub-emulsion is fully developed
    /// (the binomial fill term alone would make saturated areas grainless).
    static let positional: Float = 0.05

    /// Fill-dependent part of the variance: pₖ(1−pₖ) + positional·pₖ.
    @inline(__always) static func spread(_ f: SIMD3<Float>) -> SIMD3<Float> {
        f * (SIMD3(repeating: 1) - f) + positional * f
    }

    /// Unscaled variance weights aₖ·Dmaxₖ·spread(pₖ) at density d.
    @inline(__always) func weights(_ c: Int, _ d: Float) -> SIMD3<Float> {
        area[c] * dmax[c] * Self.spread(fill(c, d))
    }
}

extension Developer {
    /// Grain from measured sub-emulsions (see GrainLayers). `channel` is the film layer (0 R, 1 G, 2 B).
    static func addGrainLayered(_ d: inout [Float], w: Int, h: Int, stock: FilmStock, layers g: GrainLayers, channel c: Int,
                                amount: Float, context: DevelopContext, pixelUm: Float) {
        let s48 = stock.grainRMS / 1000 * grainCalibration * amount
        if s48 < 1e-5 { return }
        let a48 = Float.pi * 24 * 24
        let wRef = g.weights(c, 1.0)
        let kappa = s48 * s48 * a48 / max(wRef.sum(), 1e-9)
        let pixA = pixelUm * pixelUm
        // The fast emulsion's dye clouds are `grainSizeUm` across; finer emulsions scale with √area.
        var invA = SIMD3<Float>.zero, nScale = SIMD3<Float>.zero
        var fields: [[Float]] = []
        for k in 0..<3 {
            let cloud = stock.grainSizeUm * g.area[c][k].squareRoot()
            let A = max(pixA, Float.pi * cloud * cloud / 4)
            invA[k] = 1 / A
            // grains per measuring area: N = Dmax·A / (κ·a)
            nScale[k] = g.dmax[c][k] * A / (kappa * g.area[c][k])
            fields.append(Noise.grain(w, h, originX: context.originX, originY: context.originY, seed: context.seed,
                                      channel: UInt32(10 + 3 * c + k), sizePx: 0.5 * cloud / pixelUm))
        }
        d.withUnsafeMutableBufferPointer { dp in
            let D = dp.baseAddress!, n = dp.count
            Parallel.rows((n + 4095) / 4096) { blocks in
                for blk in blocks {
                    let a = blk * 4096, e = min(n, a + 4096)
                    for i in a..<e {
                        let f = g.fill(c, D[i])
                        let pq = GrainLayers.spread(f)
                        let sigma = (kappa * g.area[c] * g.dmax[c] * pq * invA).squareRoot()
                        var add: Float = 0
                        for k in 0..<3 {
                            let z = fields[k][i]
                            // binomial skew (Cornish–Fisher): few developed grains -> sparse, speckly texture
                            let nk = max(nScale[k] * pq[k], 1e-6)
                            let gk = min(max((1 - 2 * f[k]) / nk.squareRoot(), -1.5), 1.5)
                            add += sigma[k] * (z + gk / 6 * (z * z - 1))
                        }
                        D[i] += add
                    }
                }
            }
        }
    }
}
