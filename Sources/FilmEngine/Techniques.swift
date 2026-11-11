import Foundation
import simd

// MARK: - Lens filters (spectral)

/// Filters on the lens, applied to the light spectrum itself — not as a channel mix — so a red filter on
/// B&W film darkens a blue sky exactly as much as that film's panchromatic sensitivity and the sky's
/// spectrum dictate. Exposure is compensated as a through-the-lens meter would (the filter factor).
public enum LensFilter: String, CaseIterable, Codable, Identifiable {
    case none
    case yellow8, deepYellow15, orange21, red25, deepRed29, yellowGreen11, green58, blue47
    case cto85B, ctb80A, warm81A, cool82A
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: "None"
        case .yellow8: "Yellow (Wratten 8)"; case .deepYellow15: "Deep yellow (15)"; case .orange21: "Orange (21)"
        case .red25: "Red (25)"; case .deepRed29: "Deep red (29)"; case .yellowGreen11: "Yellow-green (11)"
        case .green58: "Green (58)"; case .blue47: "Blue (47)"
        case .cto85B: "85B amber (daylight → tungsten film)"; case .ctb80A: "80A blue (tungsten → daylight film)"
        case .warm81A: "81A warming"; case .cool82A: "82A cooling"
        }
    }
    public var isForBW: Bool {
        switch self { case .yellow8, .deepYellow15, .orange21, .red25, .deepRed29, .yellowGreen11, .green58, .blue47: true; default: false }
    }

    @inline(__always) static func edge(_ l: Float, _ cut: Float, _ width: Float) -> Float { 1 / (1 + exp(-(l - cut) / width)) }

    /// Spectral transmittance on the 5 nm grid (approximations of the published Wratten curves:
    /// long-pass edges at the 50 % points, band-pass greens/blues, and mired-shift conversion filters
    /// defined exactly as blackbody ratios).
    var transmittance: [Float] {
        let L = Spectral.wavelengths
        func mired(_ shift: Float) -> [Float] {
            let t1: Float = 5500, t2 = 1e6 / (1e6 / t1 + shift)
            let r = L.map { Spectral.planck($0, t2) / Spectral.planck($0, t1) }
            let m = r.max() ?? 1
            return r.map { 0.95 * $0 / m }
        }
        switch self {
        case .none: return [Float](repeating: 1, count: Spectral.count)
        case .yellow8: return L.map { 0.01 + 0.91 * Self.edge($0, 482, 9) }
        case .deepYellow15: return L.map { 0.005 + 0.91 * Self.edge($0, 515, 8) }
        case .orange21: return L.map { 0.003 + 0.91 * Self.edge($0, 555, 8) }
        case .red25: return L.map { 0.002 + 0.91 * Self.edge($0, 592, 7) }
        case .deepRed29: return L.map { 0.001 + 0.9 * Self.edge($0, 615, 6) }
        case .yellowGreen11: return L.map { 0.02 + 0.85 * Self.edge($0, 475, 10) * (1 - 0.55 * Self.edge($0, 605, 12)) }
        case .green58: return L.map { 0.005 + 0.62 * Self.edge($0, 497, 8) * (1 - Self.edge($0, 588, 9)) }
        case .blue47: return L.map { 0.005 + 0.55 * (1 - Self.edge($0, 503, 8)) * Self.edge($0, 395, 8) + 0.4 * Self.edge($0, 705, 10) }
        case .cto85B: return mired(131)
        case .ctb80A: return mired(-131)
        case .warm81A: return mired(18)
        case .cool82A: return mired(-18)
        }
    }

    /// Filter factor in stops for grey under daylight on a flat panchromatic response (for display).
    public var factorStops: Float {
        let t = transmittance, w = Spectral.yBar
        let a = zip(t, w).map { $0.0 * $0.1 }.reduce(0, +), b = w.reduce(0, +)
        return log2(b / max(a, 1e-6))
    }
}

// MARK: - Cross-processing (E-6 slide film in C-41)

extension MeasuredData {
    private static var synthetic: [String: MeasuredProfile] = [:]
    private static let syntheticLock = NSLock()

    /// Measured profiles plus derived ones (cross-processed slide films).
    static func profile(_ id: String) -> MeasuredProfile? {
        if let p = profiles[id] { return p }
        syntheticLock.lock(); defer { syntheticLock.unlock() }
        if let p = synthetic[id] { return p }
        guard id.hasSuffix(".xpro"), let slide = profiles[String(id.dropLast(5))] else { return nil }
        let p = crossProcessed(slide, id: id)
        synthetic[id] = p
        return p
    }

    /// A slide film developed as a negative: C-41's colour developer acts directly on the exposed silver,
    /// so each layer forms dye where the E-6 first developer would have *removed* it. The negative's
    /// density is the measured slide curve mirrored about its D-max (scaled to C-41's shorter, gentler
    /// development), the base is the slide's clear base — no orange mask — and the dyes are the slide's
    /// own, which have none of a negative film's masking couplers. Printed on negative paper, that missing
    /// mask is what gives cross-processing its high contrast and strong, uncorrectable colour crossovers.
    static let crossDevelopment: Float = 0.72
    static func crossProcessed(_ s: MeasuredProfile, id: String) -> MeasuredProfile {
        let curves = s.curves.map { c -> [Float] in
            let mx = c.max() ?? 3
            return c.map { max(mx - $0, 0) * crossDevelopment }
        }
        let layers = s.layerCurves.map { ch in ch.map { sub -> [Float] in
            let mx = sub.max() ?? 1
            return sub.map { max(mx - $0, 0) * crossDevelopment }
        } }
        return MeasuredProfile(id: id, name: s.name + " (C-41)", type: "negative", support: s.support,
                               referenceIlluminant: s.referenceIlluminant, sensitivity: s.sensitivity, dyes: s.dyes,
                               base: s.base, curves: curves, layerCurves: layers, antihalation: s.antihalation)
    }
}

extension FilmStock {
    /// The same emulsion developed in C-41 (only for measured slide films).
    public var crossProcessed: FilmStock? {
        guard kind == .slide, let m = measured, MeasuredData.profiles[m] != nil else { return nil }
        var s = self
        s.id = id + ".xpro"; s.measured = m + ".xpro"
        s.kind = .colorNegative; s.name = name + " (cross-processed)"
        s.medium = .endura; s.pushProfiles = []
        s.shadowTint = .zero; s.highlightTint = .zero
        s.isCrossProcessed = true
        return s
    }
}

// MARK: - Redscale

extension FilmModel {
    /// Film loaded backwards ("redscale"): light crosses the base — and its orange mask — first, then the
    /// red-sensitive bottom layer, the green layer, the yellow filter layer and finally the blue layer.
    /// The red and green layers, normally shielded from blue by the yellow filter, now also see blue with
    /// the silver halide's own intrinsic sensitivity (peaking near 440 nm), but only what the orange mask
    /// lets through; each layer's crystals absorb part of the light the layers behind it would get.
    func redscaleSensitivities() -> [[Float]] {
        let L = Spectral.wavelengths
        let base = measured?.base ?? [Float](repeating: 0.15, count: Spectral.count)
        let tBase = base.map { pow(10, -$0) }
        let tYellow = L.map { 1 / (1 + exp(-($0 - 500) / 8)) }            // the yellow filter layer
        let intrinsic = L.map { Spectral.lobe($0, 440, 30, 25) }            // silver halide's own blue sensitivity
        let s = sensitivities
        func peakNorm(_ v: [Float]) -> [Float] { let m = v.max() ?? 1; return v.map { $0 / max(m, 1e-9) } }
        let pr: Float = s[0].max() ?? 1, pg: Float = s[1].max() ?? 1
        var r = [Float](repeating: 0, count: Spectral.count)
        for i in 0..<Spectral.count { r[i] = (s[0][i] + intrinsic[i] * pr) * tBase[i] }
        // absorption by each layer's crystals of the light it is sensitive to (≈ 0.3 density at peak)
        let absR = peakNorm(r).map { pow(10, -0.3 * $0) }
        var g = [Float](repeating: 0, count: Spectral.count)
        for i in 0..<Spectral.count { g[i] = (s[1][i] + intrinsic[i] * pg) * tBase[i] * absR[i] }
        let absG = peakNorm(g).map { pow(10, -0.3 * $0) }
        var b = [Float](repeating: 0, count: Spectral.count)
        for i in 0..<Spectral.count {
            let through: Float = tBase[i] * absR[i] * absG[i] * tYellow[i]
            b[i] = s[2][i] * through
        }
        return [r, g, b]
    }

    private static var techniqueCache: [String: ExposureTable] = [:]
    private static let techniqueLock = NSLock()

    /// Exposure table with a lens filter and/or redscale, metered through the lens: the exposure is
    /// raised so the metered layer (green for colour, red for redscale, the single layer for B&W) gets
    /// the grey exposure it would without them.
    func table(kelvin: Float?, filter: LensFilter, redscale: Bool) -> ExposureTable {
        let plain = table(kelvin: kelvin)
        if filter == .none && !redscale { return plain }
        let key = "\(stock.id)|\(kelvin.map { Int(($0 / 50).rounded()) } ?? -1)|\(filter.rawValue)|\(redscale)"
        Self.techniqueLock.lock()
        if let t = Self.techniqueCache[key] { Self.techniqueLock.unlock(); return t }
        Self.techniqueLock.unlock()
        let light = kelvin.flatMap { abs($0 - stock.balanceKelvin) > 60 ? Spectral.illuminant(kelvin: $0) : nil } ?? reference
        let tf = filter.transmittance
        let sens = redscale && stock.kind == .colorNegative ? redscaleSensitivities() : sensitivities
        var t = SpectralUpsampler.shared.exposureTable(sensitivities: sens, illuminant: (0..<Spectral.count).map { light[$0] * tf[$0] },
                                                       reference: reference).applying(hueCalibration)
        if redscale && stock.kind == .colorNegative {
            // exposureTable normalises each layer to its own sensitivity; restore the absolute loss of
            // light each layer suffers behind the base and the other layers.
            func norm(_ v: [Float]) -> Float { (0..<Spectral.count).map { v[$0] * reference[$0] }.reduce(0, +) }
            let f = (0..<3).map { norm(sens[$0]) / max(norm(sensitivities[$0]), 1e-12) }
            t = t.applying(Spectral.M3(r0: [f[0], 0, 0], r1: [0, f[1], 0], r2: [0, 0, f[2]]))
        }
        let meter = stock.kind == .blackWhite ? 0 : (redscale ? 0 : 1)
        let k = plain.exposure(0.18, 0.18, 0.18)[meter] / max(t.exposure(0.18, 0.18, 0.18)[meter], 1e-9)
        t = t.applying(Spectral.M3(r0: [k, 0, 0], r1: [0, k, 0], r2: [0, 0, k]))
        Self.techniqueLock.lock(); Self.techniqueCache[key] = t; Self.techniqueLock.unlock()
        return t
    }
}

// MARK: - Variable-contrast (multigrade) B&W paper

/// Variable-contrast paper: two emulsions, a blue-only high-contrast one and a green-sensitised
/// low-contrast one (which keeps its native blue sensitivity). The enlarger's tungsten-halogen light
/// through the contrast filter — Ilford-style grade filters, or yellow / magenta dialled into a colour
/// head — sets the share of blue in the paper's exposure, computed spectrally; that share sets the grade.
/// Grades map to the ISO paper ranges (R ≈ 180 for 00 down to ≈ 50 for grade 5).
public enum Multigrade {
    /// grade (−1 = "00") -> ISO range R.
    static let isoRange: [(Float, Float)] = [(-1, 180), (0, 160), (1, 130), (2, 110), (3, 90), (4, 70), (5, 50)]
    /// Colour-head equivalent of a grade filter (CC yellow, CC magenta); grade 2 ≈ unfiltered.
    static func filtration(grade: Float) -> (y: Float, m: Float) { (max(0, 2 - grade) * 45, max(0, grade - 2) * 45) }

    static let lamp = Spectral.enlarger(kelvin: 3200)
    static let hard = Spectral.wavelengths.map { Spectral.lobe($0, 425, 25, 28) }
    static let soft = Spectral.wavelengths.map { Spectral.lobe($0, 540, 28, 22) + 0.55 * Spectral.lobe($0, 425, 25, 28) }

    /// Share of the exposure taken by the hard (blue) emulsion behind `y`/`m` CC of filtration.
    static func blueShare(y: Float, m: Float) -> Float {
        let L = Spectral.wavelengths
        var eh: Float = 0, es: Float = 0, nh: Float = 0, ns: Float = 0
        for i in 0..<Spectral.count {
            let blueBand = 1 - LensFilter.edge(L[i], 505, 9)
            let greenBand = LensFilter.edge(L[i], 495, 9) * (1 - LensFilter.edge(L[i], 585, 9))
            let t = pow(10, -(y / 100) * blueBand - (m / 100) * greenBand)
            eh += lamp[i] * t * hard[i]; es += lamp[i] * t * soft[i]
            nh += lamp[i] * hard[i]; ns += lamp[i] * soft[i]
        }
        let h = eh / nh, s = es / ns
        return h / (h + s)
    }

    private static let gradeTable: [(share: Float, grade: Float)] = stride(from: Float(-1), through: 5, by: 0.25).map { g in
        let f = filtration(grade: g)
        return (blueShare(y: f.y, m: f.m), g)
    }

    /// Effective grade for a filtration (interpolated along the grade-filter series).
    public static func grade(y: Float, m: Float) -> Float {
        let s = blueShare(y: y, m: m)
        let t = gradeTable
        if s <= t[0].share { return t[0].grade }
        for (a, b) in zip(t, t.dropFirst()) where s <= b.share {
            return a.grade + (b.grade - a.grade) * (s - a.share) / max(b.share - a.share, 1e-6)
        }
        return t[t.count - 1].grade
    }

    /// Paper contrast (log-log slope at mid grey) for a grade, relative to grade 2 = `grade2Contrast`.
    static func contrast(grade g: Float, grade2Contrast: Float) -> Float {
        let t = isoRange
        let gg = min(max(g, t[0].0), t[t.count - 1].0)
        var r: Float = 110
        for (a, b) in zip(t, t.dropFirst()) where gg <= b.0 { r = a.1 + (b.1 - a.1) * (gg - a.0) / (b.0 - a.0); break }
        return grade2Contrast * 110 / r
    }

    public static func label(_ g: Float) -> String {
        g < -0.5 ? "00" : (g.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", g) : String(format: "%.1f", g))
    }
}

extension FilmModel {
    /// Paper slope parameter for a B&W print at `grade` with extra colour-head filtration.
    func bwPaperKp(grade: Float, ccY: Float, ccM: Float) -> Float {
        let f = Multigrade.filtration(grade: grade)
        let g = (ccY == 0 && ccM == 0) ? grade : Multigrade.grade(y: f.y + ccY, m: f.m + ccM)
        let c = Multigrade.contrast(grade: g, grade2Contrast: stock.paperContrast)
        let fm = Developer.midGreyDensity / printRange
        return c / (printRange * fm * (1 - fm))
    }
}
