import Foundation
import simd

/// Measured-reflectance spectral priors for the two kinds of surface whose film rendering depends most on
/// spectral shape the eye cannot see: human skin (NIST, 100 subjects — SkinData.swift) and green
/// vegetation (USGS Spectral Library 7, leaves, needles, grass and canopies — FoliageData.swift).
///
/// Film layers weigh wavelengths differently from the eye, so two spectra of the same colour can expose
/// film differently. Much of a film's rendering of skin — Portra's warmth — comes from skin's reflectance
/// between 600 and 700 nm. Leaves have a deep chlorophyll absorption at 670 nm, right where film's red
/// layers peak, which a smooth reconstruction fills in: measured against the USGS spectra, smooth spectra
/// over-expose the red layer by 8–20 %, rendering foliage greyer and warmer than film really does.
///
/// For such colours the reconstructed spectrum is taken from the space of *measured* spectra: mean shape +
/// 2 principal components, solved exactly to reproduce the pixel's CIE XYZ, and blended in by how typical
/// the fitted spectrum is of the measured population. To the eye nothing changes; the film sees the material.
struct SpectralPrior {
    let mean: [Float]
    let components: [[Float]]
    let sigma: [Float]
    let xyMean: SIMD2<Float>
    let xyInv: (Float, Float, Float)
    /// How much further than the measured spread the prior reaches along +PC1.
    let pc1Extension: Float
    /// Component distance (σ) of full weight, and of zero weight.
    let full: Float, cutoff: Float
    let name: String

    init(name: String, mean: [Float], components: [[Float]], sigma: [Float], xyMean: SIMD2<Float>, xyCov: [Float],
         pc1Extension: Float = 1, full: Float = 2, cutoff: Float = 3.5) {
        self.name = name; self.mean = mean; self.components = components; self.sigma = sigma; self.xyMean = xyMean
        let a = xyCov[0], b = xyCov[1], c = xyCov[2], det = a * c - b * b
        xyInv = (c / det, -b / det, a / det)
        self.pc1Extension = pc1Extension; self.full = full; self.cutoff = cutoff
    }

    /// PC1 of skin is the pigmentation (melanin) axis: blue reflectance falls and red rises together. The
    /// NIST subjects under-represent darker skin, so the prior extends 3× further along +PC1 (more melanin,
    /// the same tissue) than the measured spread; the other limits stay at the data's own.
    static let skin = SpectralPrior(name: "skin", mean: SkinData.mean, components: SkinData.components, sigma: SkinData.sigma,
                                    xyMean: SkinData.xyMean, xyCov: SkinData.xyCov, pc1Extension: 3)
    static let foliage = SpectralPrior(name: "foliage", mean: FoliageData.mean, components: FoliageData.components,
                                       sigma: FoliageData.sigma, xyMean: FoliageData.xyMean, xyCov: FoliageData.xyCov,
                                       full: 3, cutoff: 5)
    // Foliage's window is wider than skin's: 25 plant groups (many measured once) sample real vegetation's
    // variety more thinly than 100 skin subjects sample skin.
    static let all = [skin, foliage]

    /// Mahalanobis distance of a chromaticity from the measured population.
    @inline(__always) func distance(_ x: Float, _ y: Float) -> Float {
        let dx = x - xyMean.x, dy = y - xyMean.y
        let (p, q, r) = xyInv
        return (p * dx * dx + 2 * q * dx * dy + r * dy * dy).squareRoot()
    }

    /// Cheap pre-test (generous chromaticity window) before the exact spectral test on the grid.
    @inline(__always) func inRegion(_ x: Float, _ y: Float) -> Bool { distance(x, y) < 9 }
    @inline(__always) static func anyInRegion(_ x: Float, _ y: Float) -> Bool { skin.inRegion(x, y) || foliage.inRegion(x, y) }

    /// Weight from how typical the fitted spectrum is: full within `full` σ of the measured population on
    /// both components, fading to zero at `cutoff` σ — a spectral criterion, so e.g. dark and light skin
    /// alike qualify whenever a real skin spectrum explains the colour.
    func weight(componentDistance d: Float) -> Float {
        if d <= full { return 0.9 }
        if d >= cutoff { return 0 }
        let t = (d - full) / (cutoff - full)
        return 0.9 * (1 - t * t * (3 - 2 * t))
    }

    /// Measured-material spectrum reproducing `target` (XYZ with the basis's white fix) and its blend
    /// weight, or nil if no plausible spectrum of this material does.
    func spectrum(xyz target: SIMD3<Float>, weights w: [SIMD3<Float>]) -> (spectrum: [Float], weight: Float)? {
        let n = Spectral.count
        let basis = [mean, components[0], components[1]]
        var A = [[Float]](repeating: [0, 0, 0], count: 3)
        for k in 0..<3 {
            var c = SIMD3<Float>.zero
            for l in 0..<n { c += w[l] * basis[k][l] }
            for r in 0..<3 { A[r][k] = c[r] }
        }
        guard let u = SpectralUpsampler.solve3(A, [target.x, target.y, target.z]), u.x > 0 else { return nil }
        let a1 = u.y / u.x / sigma[0], a2 = u.z / u.x / sigma[1]
        let a1n = a1 > 0 ? a1 / pc1Extension : a1
        let wt = weight(componentDistance: (a1n * a1n + a2 * a2).squareRoot())
        guard wt > 0.005 else { return nil }
        let s = (0..<n).map { u.x * basis[0][$0] + u.y * basis[1][$0] + u.z * basis[2][$0] }
        guard (s.min() ?? -1) > -0.01 * (s.max() ?? 1) else { return nil }
        return (s.map { max($0, 0) }, wt)
    }

    /// The most plausible measured-material spectrum for a colour across all priors (highest weight).
    static func best(x: Float, y: Float, xyz target: SIMD3<Float>, weights w: [SIMD3<Float>]) -> (spectrum: [Float], weight: Float)? {
        var best: (spectrum: [Float], weight: Float)? = nil
        for p in all where p.inRegion(x, y) {
            if let s = p.spectrum(xyz: target, weights: w), s.weight > (best?.weight ?? 0) { best = s }
        }
        return best
    }
}
