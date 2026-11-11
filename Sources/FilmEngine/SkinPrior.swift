import Foundation
import simd

/// Measured-skin spectral prior (NIST human skin reflectance, 100 subjects — see SkinData.swift).
///
/// Film layers weigh wavelengths differently from the eye, so two spectra of the same colour can expose
/// film differently. For skin that matters: much of a film's rendering of skin — Portra's warmth — comes
/// from skin's reflectance between 600 and 700 nm. For skin-coloured pixels the reconstructed spectrum is
/// therefore taken from the space of *measured* skin spectra: mean shape + 2 principal components (98 %
/// of the variation across subjects), solved exactly to reproduce the pixel's CIE XYZ, and blended in by
/// how close the colour is to real skin chromaticities. To the eye nothing changes; the film sees skin.
enum SkinPrior {
    static let xyInv: (Float, Float, Float) = {
        let a = SkinData.xyCov[0], b = SkinData.xyCov[1], c = SkinData.xyCov[2]
        let det = a * c - b * b
        return (c / det, -b / det, a / det)
    }()

    /// Mahalanobis distance of a chromaticity from the measured skin population.
    @inline(__always) static func distance(_ x: Float, _ y: Float) -> Float {
        let dx = x - SkinData.xyMean.x, dy = y - SkinData.xyMean.y
        let (p, q, r) = xyInv
        return (p * dx * dx + 2 * q * dx * dy + r * dy * dy).squareRoot()
    }

    /// Cheap pre-test (generous chromaticity window) before the exact spectral test on the grid.
    @inline(__always) static func inRegion(_ x: Float, _ y: Float) -> Bool { distance(x, y) < 9 }

    /// Weight from how typical the fitted skin spectrum is: full within 2 σ of the measured population on
    /// both components, fading to zero at 3.5 σ — a spectral criterion, so dark and light skin alike
    /// qualify whenever a real skin spectrum explains the colour.
    static func weight(componentDistance d: Float) -> Float {
        if d <= 2 { return 0.9 }
        if d >= 3.5 { return 0 }
        let t = (d - 2) / 1.5
        return 0.9 * (1 - t * t * (3 - 2 * t))
    }

    /// Skin spectrum reproducing `target` (XYZ with the basis's white fix) and its blend weight, or nil if
    /// no plausible skin spectrum does.
    static func spectrum(xyz target: SIMD3<Float>, weights w: [SIMD3<Float>]) -> (spectrum: [Float], weight: Float)? {
        let n = Spectral.count
        let basis = [SkinData.mean, SkinData.components[0], SkinData.components[1]]
        var A = [[Float]](repeating: [0, 0, 0], count: 3)
        for k in 0..<3 {
            var c = SIMD3<Float>.zero
            for l in 0..<n { c += w[l] * basis[k][l] }
            for r in 0..<3 { A[r][k] = c[r] }
        }
        guard let u = SpectralUpsampler.solve3(A, [target.x, target.y, target.z]), u.x > 0 else { return nil }
        // within the measured population (3 σ on each component)?
        let a1 = u.y / u.x / SkinData.sigma[0], a2 = u.z / u.x / SkinData.sigma[1]
        // PC1 is the pigmentation (melanin) axis: blue reflectance falls and red rises together. The NIST
        // subjects under-represent darker skin, so the prior extends 3× further along +PC1 (more melanin,
        // the same tissue) than the measured spread; the other limits stay at the data's own.
        let a1n = a1 > 0 ? a1 / 3 : a1
        let wt = weight(componentDistance: (a1n * a1n + a2 * a2).squareRoot())
        guard wt > 0.005 else { return nil }
        let s = (0..<n).map { u.x * basis[0][$0] + u.y * basis[1][$0] + u.z * basis[2][$0] }
        guard (s.min() ?? -1) > -0.01 * (s.max() ?? 1) else { return nil }
        return (s.map { max($0, 0) }, wt)
    }
}
