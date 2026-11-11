import Foundation

/// Spectral sampling, colour-matching functions and illuminants.
enum Spectral {
    static let start: Float = 380
    static let step: Float = 5
    static let count = 81                       // 380…780 nm, 5 nm (the measured film data's native step)
    static let wavelengths: [Float] = (0..<count).map { start + Float($0) * step }

    // MARK: CIE 1931 2° observer — multi-lobe analytic fit (Wyman, Sloan & Shirley 2013).

    @inline(__always) static func lobe(_ l: Float, _ mu: Float, _ s1: Float, _ s2: Float) -> Float {
        let t = (l - mu) / (l < mu ? s1 : s2)
        return exp(-0.5 * t * t)
    }
    static let xBar: [Float] = wavelengths.map {
        1.056 * lobe($0, 599.8, 37.9, 31.0) + 0.362 * lobe($0, 442.0, 16.0, 26.7) - 0.065 * lobe($0, 501.1, 20.4, 26.2)
    }
    static let yBar: [Float] = wavelengths.map { 0.821 * lobe($0, 568.8, 46.9, 40.5) + 0.286 * lobe($0, 530.9, 16.3, 31.1) }
    static let zBar: [Float] = wavelengths.map { 1.217 * lobe($0, 437.0, 11.8, 36.0) + 0.681 * lobe($0, 459.0, 26.0, 13.8) }

    // MARK: Illuminants

    /// CIE standard illuminant D65 at 10 nm (CIE 15), linearly interpolated to the grid (CIE's own
    /// recommended interpolation for D-series illuminants).
    static let d65: [Float] = wavelengths.map { l in
        let x = (l - 380) / 10, i = min(Int(x), d65at10.count - 2), t = x - Float(i)
        return d65at10[i] * (1 - t) + d65at10[i + 1] * t
    }
    static let d65at10: [Float] = [49.98, 54.65, 82.75, 91.49, 93.43, 86.68, 104.86, 117.01, 117.81, 114.86,
                               115.92, 108.81, 109.35, 107.80, 104.79, 107.69, 104.41, 104.05, 100.00, 96.33,
                               95.79, 88.69, 90.01, 89.60, 87.70, 83.29, 83.70, 80.03, 80.21, 82.28,
                               78.28, 69.72, 71.61, 74.35, 61.60, 69.89, 75.09, 63.59, 46.42, 66.81, 63.38]

    static func planck(_ l: Float, _ t: Float) -> Float {
        let lm = Double(l) * 1e-9
        return Float(1 / (pow(lm, 5) * (exp(1.4388e-2 / (lm * Double(t))) - 1)))
    }

    // CIE daylight components S0, S1, S2 (CIE 15:2004, 380…780 nm at 10 nm). Self-check: they
    // reproduce the tabulated D65 above to 0.03 % at every wavelength.
    static let s0at10: [Float] = [63.4, 65.8, 94.8, 104.8, 105.9, 96.8, 113.9, 125.6, 125.5, 121.3, 121.3, 113.5, 113.1, 110.8,
                                  106.5, 108.8, 105.3, 104.4, 100.0, 96.0, 95.1, 89.1, 90.5, 90.3, 88.4, 84.0, 85.1, 81.9, 82.6,
                                  84.9, 81.3, 71.9, 74.3, 76.4, 63.3, 71.7, 77.0, 65.2, 47.7, 68.6, 65.0]
    static let s1at10: [Float] = [38.5, 35.0, 43.4, 46.3, 43.9, 37.1, 36.7, 35.9, 32.6, 27.9, 24.3, 20.1, 16.2, 13.2, 8.6, 6.1,
                                  4.2, 1.9, 0.0, -1.6, -3.5, -3.5, -5.8, -7.2, -8.6, -9.5, -10.9, -10.7, -12.0, -14.0, -13.6,
                                  -12.0, -13.3, -12.9, -10.6, -11.6, -12.2, -10.2, -7.8, -11.2, -10.4]
    static let s2at10: [Float] = [3.0, 1.2, -1.1, -0.5, -0.7, -1.2, -2.6, -2.9, -2.8, -2.6, -2.6, -1.8, -1.5, -1.3, -1.2, -1.0,
                                  -0.5, -0.3, 0.0, 0.2, 0.5, 2.1, 3.2, 4.1, 4.7, 5.1, 6.7, 7.3, 8.6, 9.8, 10.2, 8.3, 9.6, 8.5,
                                  7.0, 7.6, 8.0, 6.7, 5.2, 7.4, 6.8]

    static func resample10(_ t: [Float]) -> [Float] {
        wavelengths.map { l in
            let x = (l - 380) / 10, i = min(Int(x), t.count - 2), f = x - Float(i)
            return t[i] * (1 - f) + t[i + 1] * f
        }
    }
    static let s0 = resample10(s0at10), s1 = resample10(s1at10), s2 = resample10(s2at10)

    /// CIE daylight illuminant D_T (4000…25000 K), relative SPD.
    static func daylight(kelvin: Float) -> [Float] {
        let t = Double(min(max(kelvin, 4000), 25000))
        let x = t <= 7000 ? -4.6070e9 / pow(t, 3) + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
                          : -2.0064e9 / pow(t, 3) + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
        let y = -3 * x * x + 2.87 * x - 0.275
        let m = 0.0241 + 0.2562 * x - 0.7341 * y
        let m1 = Float((-1.3515 - 1.7703 * x + 5.9114 * y) / m), m2 = Float((0.0300 - 31.4424 * x + 30.0717 * y) / m)
        return (0..<count).map { s0[$0] + m1 * s1[$0] + m2 * s2[$0] }
    }

    /// Light at a correlated colour temperature, normalised to D65's luminance: a blackbody up to
    /// 3500 K (tungsten, CIE A is a 2856 K blackbody), the CIE daylight series from 4500 K (D50, D55,
    /// D65 … exactly), and a blend in between.
    static func illuminant(kelvin t: Float) -> [Float] {
        let tt = min(max(t, 1800), 25000)
        let pb = wavelengths.map { planck($0, tt) }
        let s: [Float]
        if tt <= 3500 { s = pb }
        else {
            let dl = daylight(kelvin: tt)
            if tt >= 4500 { s = dl } else {
                let k = (tt - 3500) / 1000
                let n1 = zip(dl, yBar).map(*).reduce(0, +), n2 = zip(pb, yBar).map(*).reduce(0, +)
                s = (0..<count).map { dl[$0] * k + pb[$0] * n1 / n2 * (1 - k) }
            }
        }
        let y = zip(s, yBar).map(*).reduce(0, +)
        let y65 = zip(d65, yBar).map(*).reduce(0, +)
        return s.map { $0 * y65 / y }
    }

    /// ISO 3664 viewing light for prints and transparencies (D50).
    static let d50 = illuminant(kelvin: 5003)

    /// Spectrum -> CIE XYZ, normalised so that a perfect white under D65 has Y = 1.
    static func xyz(_ spd: [Float]) -> SIMD3<Float> {
        var x: Float = 0, y: Float = 0, z: Float = 0
        for i in 0..<count { x += spd[i] * xBar[i]; y += spd[i] * yBar[i]; z += spd[i] * zBar[i] }
        return SIMD3(x, y, z) / whiteY
    }
    static let whiteY: Float = zip(d65, yBar).map(*).reduce(0, +)

    // MARK: Colour spaces

    struct M3 {
        var r0: SIMD3<Float>, r1: SIMD3<Float>, r2: SIMD3<Float>
        func apply(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3((r0 * v).sum(), (r1 * v).sum(), (r2 * v).sum()) }
        /// self ∘ other (apply `other` first).
        func compose(_ o: M3) -> M3 {
            let c0 = SIMD3(o.r0.x, o.r1.x, o.r2.x), c1 = SIMD3(o.r0.y, o.r1.y, o.r2.y), c2 = SIMD3(o.r0.z, o.r1.z, o.r2.z)
            func row(_ r: SIMD3<Float>) -> SIMD3<Float> { SIMD3((r * c0).sum(), (r * c1).sum(), (r * c2).sum()) }
            return M3(r0: row(r0), r1: row(r1), r2: row(r2))
        }
    }
    static let rec2020ToXYZ = M3(r0: [0.6369580, 0.1446169, 0.1688810], r1: [0.2627002, 0.6779981, 0.0593017], r2: [0.0, 0.0280727, 1.0609851])
    static let xyzToSRGB = M3(r0: [3.2404542, -1.5371385, -0.4985314], r1: [-0.9692660, 1.8760108, 0.0415560], r2: [0.0556434, -0.2040259, 1.0572252])
    static let xyzToRec2020 = M3(r0: [1.7166512, -0.3556708, -0.2533663], r1: [-0.6666844, 1.6164812, 0.0157685], r2: [0.0176399, -0.0427706, 0.9421031])
    static let rec2020ToSRGB = xyzToSRGB.compose(rec2020ToXYZ)
    static let srgbToXYZ = M3(r0: [0.4124564, 0.3575761, 0.1804375], r1: [0.2126729, 0.7151522, 0.0721750], r2: [0.0193339, 0.1191920, 0.9503041])

    // Bradford chromatic adaptation
    static let bradford = M3(r0: [0.8951, 0.2664, -0.1614], r1: [-0.7502, 1.7135, 0.0367], r2: [0.0389, -0.0685, 1.0296])
    static let bradfordInv = M3(r0: [0.9869929, -0.1470543, 0.1599627], r1: [0.4323053, 0.5183603, 0.0492912], r2: [-0.0085287, 0.0400428, 0.9684867])
    static let d65White = SIMD3<Float>(0.95047, 1.0, 1.08883)

    /// Matrix adapting colours seen relative to `white` to D65 (von Kries in Bradford space).
    static func adaptation(from white: SIMD3<Float>) -> (SIMD3<Float>) -> SIMD3<Float> {
        let src = bradford.apply(white), dst = bradford.apply(d65White)
        let k = dst / src
        return { bradfordInv.apply(bradford.apply($0) * k) }
    }

    static func lab(_ xyz: SIMD3<Float>) -> SIMD3<Float> {
        func f(_ t: Float) -> Float { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        let v = xyz / d65White
        let fx = f(v.x), fy = f(v.y), fz = f(v.z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    // MARK: Band shapes

    /// Schott KG3 heat-absorbing glass (enlarger), approximate transmission.
    static let kg3: [Float] = wavelengths.map { 1 / (1 + exp(($0 - 712) / 16)) }

    /// Enlarger lamp: tungsten-halogen behind a KG3 heat filter ("TH-KG3" in the paper datasheets).
    static func enlarger(kelvin: Float) -> [Float] {
        let p = wavelengths.map { planck($0, kelvin) }
        let m = p.max() ?? 1
        return (0..<count).map { p[$0] / m * kg3[$0] }
    }

    /// Asymmetric Gaussian band, peak 1.
    static func band(peak: Float, left: Float, right: Float) -> [Float] {
        wavelengths.map { lobe($0, peak, left, right) }
    }
}

/// A spectral curve built from a few asymmetric Gaussian lobes.
public struct Lobe: Hashable {
    public var peak: Float, left: Float, right: Float, weight: Float
    public init(_ peak: Float, _ left: Float, _ right: Float, _ weight: Float = 1) {
        self.peak = peak; self.left = left; self.right = right; self.weight = weight
    }
}

extension Array where Element == Lobe {
    var sampled: [Float] {
        var out = [Float](repeating: 0, count: Spectral.count)
        for l in self {
            let b = Spectral.band(peak: l.peak, left: l.left, right: l.right)
            for i in 0..<out.count { out[i] += l.weight * b[i] }
        }
        return out
    }
}
