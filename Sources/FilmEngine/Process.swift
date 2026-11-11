import Foundation
import simd

// MARK: - Agitation and developer exhaustion

/// How the developer is moved over the film. Datasheet curves are measured with continuous (machine
/// or rotary) agitation; less agitation lets developer exhaust locally.
public enum Agitation: String, CaseIterable, Codable, Identifiable {
    case continuous, intermittent, stand
    public var id: String { rawValue }
    public var label: String {
        switch self { case .continuous: "Continuous"; case .intermittent: "Intermittent"; case .stand: "Stand (1 hr)" }
    }

    /// strength s: fractional loss of activity per unit density developed nearby;
    /// spread: diffusion length of fresh developer (µm); drag: share that sinks downward along the film
    /// (bromide drag); dragUm: how far it sinks; compensation: how much large areas are exhausted
    /// relative to the datasheet (0 = none, 1 = full compensating development).
    var params: (s: Float, spreadUm: Float, drag: Float, dragUm: Float, compensation: Float) {
        switch self {
        case .continuous: (0.03, 60, 0, 0, 0)
        case .intermittent: (0.08, 250, 0.15, 1500, 0.4)
        case .stand: (0.20, 900, 0.45, 3500, 1.0)
        }
    }
}

extension Developer {
    /// Developer exhaustion. Development consumes developer in proportion to the silver/dye it forms;
    /// fresh developer only reaches the emulsion by diffusion over a distance set by the agitation,
    /// and exhausted, bromide-laden developer is denser and sinks along the film (the reel's axis is
    /// vertical, so it runs across the frame's short side) — the streaks of "bromide drag".
    ///
    /// Activity a(x) = 1 − s·(K ∗ D̄)(x), with D̄ the mean density over the three layers (they share
    /// the developer) and K the diffusion + drag kernel. Density is rescaled by a(x) relative to what a
    /// uniform area at the datasheet reference sees, so continuous agitation leaves large areas on the
    /// measured curve and only adds the edge effects (Eberhard / Mackie lines); stand development also
    /// compresses large dense areas (compensation) while small highlights stay dense.
    static func applyExhaustion(_ r: inout [Float], _ g: inout [Float], _ b: inout [Float], w: Int, h: Int,
                                agitation: Agitation, midDensity: Float, pixelUm: Float, mono: Bool,
                                reversal: Bool = false, dmax: Float = 3) {
        let p = agitation.params
        let n = r.count
        // Reversal film: what exhausts the (first) developer is the silver of the *exposed* areas, i.e.
        // the dye that will be missing: work on developed = D-max − D, and map back afterwards.
        if reversal {
            for i in 0..<n { r[i] = dmax - r[i]; g[i] = dmax - g[i]; b[i] = dmax - b[i] }
        }
        defer {
            if reversal { for i in 0..<n { r[i] = dmax - r[i]; g[i] = dmax - g[i]; b[i] = dmax - b[i] } }
        }
        let midDensity = reversal ? dmax - midDensity : midDensity
        var mean = [Float](repeating: 0, count: n)
        for i in 0..<n { mean[i] = mono ? r[i] : (r[i] + g[i] + b[i]) / 3 }
        var field = Blur.gaussian(mean, w, h, sigma: max(p.spreadUm / pixelUm, 0.5))
        if p.drag > 0 {
            // One-sided exponential smear "downward" along the film width (the frame's short side).
            let alongY = w >= h
            let len = max(p.dragUm / pixelUm, 1)
            let k = exp(-1 / len)
            var dragged = field
            if alongY {
                for x in 0..<w {
                    var acc = field[x]
                    for y in 0..<h { let i = y * w + x; acc = acc * k + field[i] * (1 - k); dragged[i] = acc }
                }
            } else {
                for y in 0..<h {
                    var acc = field[y * w]
                    for x in 0..<w { let i = y * w + x; acc = acc * k + field[i] * (1 - k); dragged[i] = acc }
                }
            }
            for i in 0..<n { field[i] = field[i] * (1 - p.drag) + dragged[i] * p.drag }
        }
        let s = p.s, comp = p.compensation
        func scale(_ i: Int) -> Float {
            let ref = comp * midDensity + (1 - comp) * mean[i]
            return max(1 - s * field[i], 0.2) / max(1 - s * ref, 0.2)
        }
        for i in 0..<n {
            let k = scale(i)
            r[i] *= k
            if !mono { g[i] *= k; b[i] *= k }
        }
    }
}

// MARK: - Expired film

/// How the film was kept before it was shot.
public enum Storage: String, CaseIterable, Codable, Identifiable {
    case freezer, fridge, room, hot
    public var id: String { rawValue }
    public var label: String {
        switch self { case .freezer: "Freezer"; case .fridge: "Fridge"; case .room: "Room temperature"; case .hot: "Hot (car, attic)" }
    }
    /// Chemical ageing rate relative to room temperature (roughly Arrhenius: ×2–3 per 10 °C).
    var rate: Float {
        switch self { case .freezer: 0.08; case .fridge: 0.3; case .room: 1; case .hot: 2.5 }
    }
}

/// Latent-image and emulsion ageing, per layer.
///
/// Chemical ageing (slowed by cold): speed loss (≈ 1 stop per decade at room temperature, the
/// blue-sensitive top layer fastest), rising chemical fog (most in the blue-sensitive / yellow layer) and
/// a flatter curve. Background radiation (cosmic rays, natural radioactivity) fogs film regardless of
/// temperature, in proportion to its speed — why ISO 800–3200 film goes grey even from the freezer.
struct Aging {
    var speedLoss = SIMD3<Float>(repeating: 0)   // log10 exposure
    var fog = SIMD3<Float>(repeating: 0)         // density (negatives) / fractional D-max loss (slides)
    var gain: Float = 1

    static let none = Aging()

    init() {}
    init(years: Float, storage: Storage, iso: Int) {
        guard years > 0.05 else { return }
        let chem = min(years / 10 * storage.rate, 4)        // effective decades at room temperature
        let rad = min(years / 10 * Float(iso) / 400, 4)      // radiation dose relative to ISO 400 per decade
        speedLoss = SIMD3(0.25, 0.28, 0.35) * chem + SIMD3(repeating: 0.05) * rad
        fog = SIMD3(0.05, 0.07, 0.12) * chem + SIMD3(repeating: 0.05) * rad
        gain = max(1 - 0.06 * chem - 0.02 * rad, 0.6)
    }

    var isNone: Bool { speedLoss == .zero && fog == .zero && gain == 1 }
}
