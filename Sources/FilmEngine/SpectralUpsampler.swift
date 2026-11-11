import Foundation
import simd

/// RGB -> reflectance spectrum by spectral primary decomposition (after Mallett & Yuksel 2019,
/// "Spectral Primary Decomposition for Rendering with sRGB Reflectance").
///
/// Three basis spectra B_r, B_g, B_b are solved once so that
///   • B_r + B_g + B_b = 1 at every wavelength (white is a flat, perfect reflector),
///   • 0 ≤ B ≤ 1 (every in-gamut colour is a physically valid reflectance),
///   • each basis renders exactly its linear-sRGB primary under D65,
///   • and they are as smooth as possible (no needle or U-shaped metamers).
/// A colour's spectrum is then r·B_r + g·B_g + b·B_b. Because it is linear, the exposure of any film
/// layer under any light is an exact 3×3 matrix — no hidden deep-red or UV reflectance that the eye
/// ignores but film records.
final class SpectralUpsampler {
    static let shared = SpectralUpsampler()
    /// basis[primary][wavelength]
    private(set) var basis: [[Float]] = []

    static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Emulsion98")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spd-basis-v1-\(Spectral.count).bin")
    }

    private init() {
        let n = Spectral.count
        if let data = try? Data(contentsOf: Self.cacheURL), data.count == 3 * n * MemoryLayout<Float>.stride {
            let all: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            basis = (0..<3).map { Array(all[($0 * n)..<(($0 + 1) * n)]) }
            return
        }
        basis = Self.solveBasis()
        try? basis.flatMap { $0 }.withUnsafeBytes { Data($0) }.write(to: Self.cacheURL)
    }

    /// Spectrum of a linear-sRGB colour.
    func spectrum(srgb c: SIMD3<Float>) -> [Float] {
        (0..<Spectral.count).map { c.x * basis[0][$0] + c.y * basis[1][$0] + c.z * basis[2][$0] }
    }

    /// CIE weights under D65 (perfect white → Y = 1).
    static var weights: [SIMD3<Float>] {
        (0..<Spectral.count).map { SIMD3(Spectral.xBar[$0], Spectral.yBar[$0], Spectral.zBar[$0]) * Spectral.d65[$0] / Spectral.whiteY }
    }

    /// Projected-gradient solve with augmented-Lagrangian colour constraints.
    static func solveBasis() -> [[Float]] {
        let n = Spectral.count
        let w = weights
        let M = Spectral.srgbToXYZ
        let targets: [SIMD3<Float>] = [SIMD3(M.r0.x, M.r1.x, M.r2.x), SIMD3(M.r0.y, M.r1.y, M.r2.y), SIMD3(M.r0.z, M.r1.z, M.r2.z)]
        // The analytic CMF fit's white differs very slightly from the sRGB white; rescale the targets so
        // the three primaries still sum to the white a flat spectrum actually produces.
        let whiteSpec = w.reduce(SIMD3<Float>.zero, +)
        let fix = whiteSpec / (targets[0] + targets[1] + targets[2])
        let T = targets.map { $0 * fix }

        var B: [[Float]] = [Spectral.band(peak: 620, left: 40, right: 120),
                            Spectral.band(peak: 540, left: 40, right: 40),
                            Spectral.band(peak: 440, left: 120, right: 40)]
        for l in 0..<n { let s = B[0][l] + B[1][l] + B[2][l]; for i in 0..<3 { B[i][l] /= s } }

        var lambda = [SIMD3<Float>](repeating: .zero, count: 3)
        var mu: Float = 20
        for outer in 0..<60 {
            let step: Float = 0.5 / (8 + mu * 0.25)
            for _ in 0..<1500 {
                var G = [[Float]](repeating: [Float](repeating: 0, count: n), count: 3)
                for i in 0..<3 {
                    for l in 1..<(n - 1) {        // roughness (second differences)
                        let d2 = B[i][l - 1] - 2 * B[i][l] + B[i][l + 1]
                        G[i][l - 1] += 2 * d2; G[i][l] -= 4 * d2; G[i][l + 1] += 2 * d2
                    }
                    var c = SIMD3<Float>.zero
                    for l in 0..<n { c += w[l] * B[i][l] }
                    let g = lambda[i] + mu * (c - T[i])
                    for l in 0..<n { G[i][l] += (g * w[l]).sum() }
                }
                for l in 0..<n {
                    let v = projectSimplex(SIMD3(B[0][l] - step * G[0][l], B[1][l] - step * G[1][l], B[2][l] - step * G[2][l]))
                    B[0][l] = v.x; B[1][l] = v.y; B[2][l] = v.z
                }
            }
            var maxErr: Float = 0
            for i in 0..<3 {
                var c = SIMD3<Float>.zero
                for l in 0..<n { c += w[l] * B[i][l] }
                lambda[i] += mu * (c - T[i])
                maxErr = max(maxErr, abs(c - T[i]).max())
            }
            if maxErr < 1e-5 && outer > 5 { break }
            mu = min(mu * 1.5, 3000)
        }
        return B
    }

    /// Euclidean projection onto the probability simplex {x ≥ 0, Σx = 1}.
    static func projectSimplex(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let u = [v.x, v.y, v.z].sorted(by: >)
        var css: Float = 0, theta: Float = 0
        for j in 0..<3 {
            css += u[j]
            let t = (css - 1) / Float(j + 1)
            if u[j] - t > 0 { theta = t }
        }
        return simd_max(v - SIMD3(repeating: theta), .zero)
    }

    /// Cramer's-rule solve of a 3×3 system.
    static func solve3(_ a: [[Float]], _ b: [Float]) -> SIMD3<Float>? {
        func d(_ m: [[Float]]) -> Float {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let det = d(a)
        if abs(det) < 1e-20 { return nil }
        var out = SIMD3<Float>.zero
        for k in 0..<3 {
            var m = a
            for i in 0..<3 { m[i][k] = b[i] }
            out[k] = d(m) / det
        }
        return out
    }

    /// Max colour error of the basis (XYZ), for diagnostics.
    func basisError() -> Float {
        let w = Self.weights, M = Spectral.srgbToXYZ
        let targets: [SIMD3<Float>] = [SIMD3(M.r0.x, M.r1.x, M.r2.x), SIMD3(M.r0.y, M.r1.y, M.r2.y), SIMD3(M.r0.z, M.r1.z, M.r2.z)]
        let fix = w.reduce(SIMD3<Float>.zero, +) / (targets[0] + targets[1] + targets[2])
        var e: Float = 0
        for i in 0..<3 {
            var c = SIMD3<Float>.zero
            for l in 0..<Spectral.count { c += w[l] * basis[i][l] }
            e = max(e, abs(c - targets[i] * fix).max())
        }
        return e
    }

    // MARK: Wide-gamut colours

    /// Chromaticity grid (CIE xy) of spectra for colours outside the sRGB gamut — P3 phone photos and
    /// saturated RAW colours. Inside sRGB the basis is exact; outside it, a colour with a negative sRGB
    /// component has no non-negative combination of the basis, and the linear extrapolation would ask
    /// the film to record negative light at some wavelengths. Instead each out-of-gamut chromaticity gets
    /// the closest physically valid spectrum to its gamut-clipped basis spectrum (Dykstra projection onto
    /// {s ≥ 0, CIE XYZ(s) = target}); the correction is a smooth sum of colour-matching curves. At the
    /// spectral locus the nearest non-negative spectrum is used; far outside it, the linear path.
    static let gamutN = 128
    static let gamutX: ClosedRange<Float> = 0...0.8, gamutY: ClosedRange<Float> = 0...0.9
    private(set) lazy var gamutSpectra: [[Float]?] = Self.loadOrSolveGamut(basis: basis)

    static var gamutCacheURL: URL {
        cacheURL.deletingLastPathComponent().appendingPathComponent("gamut-v6-\(Spectral.count)-\(gamutN).bin")
    }

    /// XYZ (standard D65 observer, X+Y+Z = 1) of grid node (i, j).
    static func gamutNodeXYZ(_ i: Int, _ j: Int) -> SIMD3<Float> {
        let x = gamutX.lowerBound + (gamutX.upperBound - gamutX.lowerBound) * Float(i) / Float(gamutN - 1)
        let y = gamutY.lowerBound + (gamutY.upperBound - gamutY.lowerBound) * Float(j) / Float(gamutN - 1)
        return SIMD3(x, y, 1 - x - y)
    }

    private static func loadOrSolveGamut(basis: [[Float]]) -> [[Float]?] {
        let n = Spectral.count, N = gamutN * gamutN
        if let data = try? Data(contentsOf: gamutCacheURL), data.count == N * n * MemoryLayout<Float>.stride {
            let all: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return (0..<N).map { k in all[k * n].isNaN ? nil : Array(all[(k * n)..<((k + 1) * n)]) }
        }
        let out = solveGamut(basis: basis)
        var flat = [Float](repeating: .nan, count: N * n)
        for k in 0..<N { if let sp = out[k] { for l in 0..<n { flat[k * n + l] = sp[l] } } }
        try? flat.withUnsafeBytes { Data($0) }.write(to: gamutCacheURL)
        return out
    }

    static func solveGamut(basis: [[Float]]) -> [[Float]?] {
        let n = Spectral.count, G = gamutN
        let w = weights
        let M = srgbFix()
        // Gram matrix of the colour constraints and its inverse (for the affine projection).
        var gram = [[Float]](repeating: [0, 0, 0], count: 3)
        for a in 0..<3 { for b in 0..<3 { gram[a][b] = (0..<n).map { w[$0][a] * w[$0][b] }.reduce(0, +) } }
        var gInv = [[Float]](repeating: [0, 0, 0], count: 3)
        for k in 0..<3 { var e: [Float] = [0, 0, 0]; e[k] = 1; let c = solve3(gram, e)!; for r in 0..<3 { gInv[r][k] = c[r] } }

        var result = [[Float]?](repeating: nil, count: G * G)
        let lock = NSLock()
        Parallel.rows(G * G) { range in
            for k in range {
                let i = k % G, j = k / G
                let xyz = gamutNodeXYZ(i, j)
                if xyz.z < 0 { continue }
                let c = Spectral.xyzToSRGB.apply(xyz)
                let target = xyz * M.fix
                let c0 = simd_max(c, .zero)
                var x = (0..<n).map { c0.x * basis[0][$0] + c0.y * basis[1][$0] + c0.z * basis[2][$0] }
                if c.min() >= 0 {
                    // In gamut: smooth basis — blended toward a measured-skin spectrum for skin colours.
                    if SkinPrior.inRegion(xyz.x, xyz.y), let skin = SkinPrior.spectrum(xyz: target, weights: w) {
                        for l in 0..<n { x[l] = x[l] * (1 - skin.weight) + skin.spectrum[l] * skin.weight }
                    }
                    lock.lock(); result[k] = x; lock.unlock(); continue
                }
                var p = [Float](repeating: 0, count: n), q = p, y = p
                for _ in 0..<3000 {
                    // affine projection of x + p
                    var r = SIMD3<Float>.zero
                    for l in 0..<n { y[l] = x[l] + p[l]; r += w[l] * y[l] }
                    let d = r - target
                    let lam = SIMD3((SIMD3(gInv[0][0], gInv[0][1], gInv[0][2]) * d).sum(),
                                    (SIMD3(gInv[1][0], gInv[1][1], gInv[1][2]) * d).sum(),
                                    (SIMD3(gInv[2][0], gInv[2][1], gInv[2][2]) * d).sum())
                    for l in 0..<n {
                        let yl = y[l] - (w[l] * lam).sum()
                        p[l] = y[l] - yl
                        y[l] = yl
                    }
                    // non-negativity
                    for l in 0..<n {
                        let v = y[l] + q[l]
                        x[l] = max(v, 0)
                        q[l] = v - x[l]
                    }
                }
                var r = SIMD3<Float>.zero
                for l in 0..<n { r += w[l] * x[l] }
                let err = abs(r - target).max() / max(target.sum(), 1e-6)
                // On or beyond the spectral locus no valid spectrum matches exactly; the nearest non-negative one is
                // a physical gamut mapping (far better than asking the film to record negative light).
                if err < 0.25 { lock.lock(); result[k] = x; lock.unlock() }
            }
        }
        return result
    }

    /// The basis's tiny CMF-fit white correction.
    static func srgbFix() -> (fix: SIMD3<Float>, w: [SIMD3<Float>]) {
        let w = weights, M = Spectral.srgbToXYZ
        let t = SIMD3(M.r0.x, M.r1.x, M.r2.x) + SIMD3(M.r0.y, M.r1.y, M.r2.y) + SIMD3(M.r0.z, M.r1.z, M.r2.z)
        return (w.reduce(SIMD3<Float>.zero, +) / t, w)
    }

    /// Exposure of each sensitivity curve to each basis primary under `illuminant`, normalised so a
    /// perfect white under `reference` gives 1.
    func exposureTable(sensitivities: [[Float]], illuminant: [Float], reference: [Float]) -> ExposureTable {
        var rows = [SIMD3<Float>](repeating: .zero, count: 3)
        var norms: [Float] = [1, 1, 1]
        for k in 0..<min(3, sensitivities.count) {
            let s = sensitivities[k]
            norms[k] = (0..<Spectral.count).map { s[$0] * reference[$0] }.reduce(0, +)
            for p in 0..<3 {
                rows[k][p] = (0..<Spectral.count).map { basis[p][$0] * illuminant[$0] * s[$0] }.reduce(0, +) / norms[k]
            }
        }
        let filmFromSRGB = Spectral.M3(r0: rows[0], r1: rows[1], r2: rows[2])
        let linear = filmFromSRGB.compose(Spectral.rec2020ToSRGB)
        // Out-of-gamut grid: exposure per unit X+Y+Z at every node (linear path where no valid spectrum).
        let G = Self.gamutN, spectra = gamutSpectra
        let fromXYZ = filmFromSRGB.compose(Spectral.xyzToSRGB)
        var grid = [SIMD3<Float>](repeating: .zero, count: G * G)
        let weightsK: [[Float]] = (0..<3).map { k in
            let s = sensitivities[min(k, sensitivities.count - 1)]
            return (0..<Spectral.count).map { illuminant[$0] * s[$0] / norms[k] }
        }
        for k in 0..<(G * G) {
            if let sp = spectra[k] {
                var e = SIMD3<Float>.zero
                for l in 0..<Spectral.count { e += SIMD3(weightsK[0][l], weightsK[1][l], weightsK[2][l]) * sp[l] }
                grid[k] = e
            } else {
                grid[k] = fromXYZ.apply(Self.gamutNodeXYZ(k % G, k / G))
            }
        }
        return ExposureTable(matrix: linear, post: Spectral.M3(r0: [1, 0, 0], r1: [0, 1, 0], r2: [0, 0, 1]), grid: grid)
    }
}

/// Linear-Rec.2020 -> film layer exposure. In the sRGB gamut it is an exact 3×3 matrix; outside it the
/// exposure comes from physically valid wide-gamut spectra (chromaticity grid × X+Y+Z).
struct ExposureTable {
    /// Rec.2020 -> exposure (linear path, exact in gamut).
    let matrix: Spectral.M3
    /// Layer-space matrix applied to grid lookups (hue calibration, reciprocity gains…).
    let post: Spectral.M3
    let grid: [SIMD3<Float>]

    static let toSRGB = Spectral.rec2020ToSRGB
    static let toXYZ = Spectral.rec2020ToXYZ
    static let gx0 = SpectralUpsampler.gamutX.lowerBound, gy0 = SpectralUpsampler.gamutY.lowerBound
    static let gsx = Float(SpectralUpsampler.gamutN - 1) / (SpectralUpsampler.gamutX.upperBound - SpectralUpsampler.gamutX.lowerBound)
    static let gsy = Float(SpectralUpsampler.gamutN - 1) / (SpectralUpsampler.gamutY.upperBound - SpectralUpsampler.gamutY.lowerBound)

    @inline(__always) func exposure(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        let v = SIMD3(r, g, b)
        let lin = matrix.apply(v)
        let srgb = Self.toSRGB.apply(v)
        let lum = srgb.x * 0.2126 + srgb.y * 0.7152 + srgb.z * 0.0722
        guard lum > 1e-6 else { return lin }
        let xyz = Self.toXYZ.apply(v)
        let S = xyz.sum()
        guard S > 1e-6 else { return lin }
        // In gamut and not skin-coloured: exact linear path. Skin tones and out-of-gamut colours use the grid.
        if srgb.min() >= -1e-4 * lum && !SkinPrior.inRegion(xyz.x / S, xyz.y / S) { return lin }
        let fx = (xyz.x / S - Self.gx0) * Self.gsx, fy = (xyz.y / S - Self.gy0) * Self.gsy
        let N = SpectralUpsampler.gamutN
        guard fx >= 0, fy >= 0, fx < Float(N - 1), fy < Float(N - 1) else { return lin }
        let i = Int(fx), j = Int(fy), tx = fx - Float(i), ty = fy - Float(j)
        let k = j * N + i
        let e = (grid[k] * (1 - tx) + grid[k + 1] * tx) * (1 - ty) + (grid[k + N] * (1 - tx) + grid[k + N + 1] * tx) * ty
        return post.apply(e * S)
    }

    /// Same mapping with a 3×3 layer-exposure matrix applied after it.
    func applying(_ m: Spectral.M3) -> ExposureTable {
        ExposureTable(matrix: m.compose(matrix), post: m.compose(post), grid: grid)
    }
}
