import Foundation
import simd

// MARK: - Viewing light

/// The light a finished print or slide is looked at under.
///
/// The print's dyes are integrated spectrally under this light, so dye metamerism appears by itself (a
/// print's colours shift *relative to each other* under a tungsten lamp or a phosphor LED, not just as a
/// cast), and the eye's adaptation to it is only partial: in a living room under a lamp a print stays
/// warm, by candlelight warmer still. Degrees of adaptation follow CIECAM02 for typical illuminance
/// (booth ≈ 1, home lighting ≈ 0.8), lowered further for very warm light, where adaptation is known to be
/// less complete.
public enum ViewingLight: String, CaseIterable, Codable, Identifiable {
    /// The reference: a D50 viewing booth for prints, a 5000 K light box for slides, xenon for cine prints.
    case standard
    case daylight
    case tungsten
    case warmLED
    case candle
    /// Slides: a tungsten-halogen projector in a darkened room.
    case projector
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: "Viewing booth (D50)"
        case .daylight: "Daylight window"
        case .tungsten: "Tungsten lamp"
        case .warmLED: "Warm LED bulb"
        case .candle: "Candlelight"
        case .projector: "Slide projector"
        }
    }

    /// Options that make sense for a medium.
    public static func options(slide: Bool) -> [ViewingLight] {
        slide ? [.standard, .projector, .daylight, .tungsten] : [.standard, .daylight, .tungsten, .warmLED, .candle]
    }

    var adaptation: Float {
        switch self {
        case .standard: 1
        case .daylight: 0.95
        case .tungsten: 0.8
        case .warmLED: 0.8
        case .candle: 0.65
        case .projector: 0.95      // the screen is the only light: nearly complete
        }
    }

    var spectrum: [Float] {
        switch self {
        case .standard: Spectral.d50
        case .daylight: Spectral.illuminant(kelvin: 6500)
        case .tungsten: Spectral.illuminant(kelvin: 2856)     // CIE illuminant A
        case .candle: Spectral.illuminant(kelvin: 1900)
        case .projector: Spectral.illuminant(kelvin: 3300)
        case .warmLED: Self.ledSpectrum
        }
    }

    /// A 2700 K-class white LED: a 450 nm blue pump and a broad yellow-red phosphor (as typical CRI-80
    /// lamps: little deep red, a dip at 480 nm) — the spiky spectrum is what makes dyes shift under it.
    static let ledSpectrum: [Float] = {
        let s = Spectral.wavelengths.map { 0.28 * Spectral.lobe($0, 451, 9, 11) + Spectral.lobe($0, 605, 62, 58) }
        let m = s.max() ?? 1
        return s.map { $0 / m }
    }()
}

extension FilmDiagnostics {
    /// Dye metamerism and appearance of a print / slide under each viewing light: ColorChecker patches
    /// developed normally, then shown (a) fully adapted to the light — what remains is metamerism alone —
    /// and (b) with the realistic, partial adaptation. Differences in Oklab ΔE × 100 against the booth.
    public static func viewingReport(_ stock: FilmStock) -> String {
        let m = FilmModel.model(for: stock)
        guard stock.kind != .blackWhite, let src = m.displaySource else { return "\(stock.id): B&W silver is spectrally neutral (no dye metamerism)" }
        // Print / slide densities of each patch, through the full uniform chain.
        let t = m.tone(push: 0), nz = m.cachedNeutralizer(push: 0)
        let bal = m.balance(scene: m.refTable, tone: t, ev: 0, correction: 0, neutral: nz)
        func densities(_ c8: SIMD3<Float>) -> SIMD3<Float> {
            let lin = SIMD3(FilmModel.srgbDecode(c8.x / 255), FilmModel.srgbDecode(c8.y / 255), FilmModel.srgbDecode(c8.z / 255))
            let rgb = Spectral.xyzToRec2020.apply(Spectral.srgbToXYZ.apply(lin))
            let e = m.refTable.exposure(rgb.x, rgb.y, rgb.z)
            var x = SIMD3<Float>.zero
            for k in 0..<3 { x[k] = log10(max(e[k], 1e-7)) - log10(Developer.midGrey) }
            let xp = m.uniformDIR(x, t)
            return SIMD3(m.density(xp.x, 0, t), m.density(xp.y, 1, t), m.density(xp.z, 2, t))
        }
        let ds = FilmModel.checker.map(densities)
        func out(_ lut: LUT3, _ d: SIMD3<Float>) -> SIMD3<Float> {
            switch stock.kind {
            case .slide:
                let dd = SIMD3(d.x + nz.offset(0, d.x), d.y + nz.offset(1, d.y), d.z + nz.offset(2, d.z))
                return FilmModel.oklab(lut.sample(simd_max(dd * SIMD3(exp(bal.x), exp(bal.y), exp(bal.z)), .zero)))
            default:
                return FilmModel.oklab(m.renderPrint(m.negToPrint!.sample(d), balance: bal, neutral: nz, view: lut))
            }
        }
        let ref = ds.map { out(m.display!, $0) }
        var s = "\(stock.id)  (Oklab ΔE×100 vs the booth: mean / max over the 18 ColorChecker colours)\n"
        for v in ViewingLight.options(slide: stock.kind == .slide) where v != .standard {
            let full = FilmModel.displayLUT(dyes: src.dyes, base: src.base, maxIn: src.maxIn, balance: false,
                                            viewing: v.spectrum, flare: src.flare, adaptation: 1)
            let seen = m.display(for: v)!
            let a = zip(ds, ref).map { simd_length(out(full, $0.0) - $0.1) * 100 }
            let b = zip(ds, ref).map { simd_length(out(seen, $0.0) - $0.1) * 100 }
            s += String(format: "  %-20@ metamerism %4.1f / %4.1f    as seen (adaptation %.2f) %5.1f / %5.1f\n",
                        v.label as NSString, a.reduce(0, +) / Float(a.count), a.max() ?? 0, v.adaptation,
                        b.reduce(0, +) / Float(b.count), b.max() ?? 0)
        }
        return s
    }
}
