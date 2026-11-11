import Foundation
import simd

// MARK: - Archival fading of the finished picture

/// How the finished print, slide or negative was kept after processing.
public enum Keeping: String, CaseIterable, Codable, Identifiable {
    /// Dark storage: album, shoebox, slide box. Fading is chemical (thermal) and the dye couplers
    /// left in the emulsion slowly turn yellow.
    case album
    /// On display: a framed print on the wall or a slide on a light box/window. Light fading, which
    /// attacks a different dye than dark fading and bleaches some of the stain.
    case framed
    public var id: String { rawValue }
    public var label: String { self == .album ? "In an album (dark)" : "On display (light)" }
}

/// Per-dye fading kinetics of a chromogenic (or silver) image.
///
/// Dye loss is close to first order in the dye amount, so each dye keeps a fraction exp(−r·t) of its
/// density. Light fading is faster, proportionally, in thin dye deposits (the highlights and pastels
/// fade first); dark fading is nearly uniform with density. Unused couplers form a yellow stain that
/// grows with time in the dark, which is what the paper white turns into.
///
/// The rates describe the chromogenic materials of the 1970s–90s whose faded prints and slides people
/// know (after the dark-keeping and light-fading data in H. Wilhelm, *The Permanence and Care of Color
/// Photographs*, 1993): in the dark, colour paper and Eastmancolor cine prints lose cyan first and go
/// red / pink; E-6 slides lose cyan and yellow and go magenta; Kodachrome is far more stable in the dark
/// (yellow its weakest dye) but poor on display; in the light, papers lose magenta and yellow and go
/// cyan-blue. Modern papers (Crystal Archive, Endura) fade several times more slowly than this.
struct Fade {
    /// Fractional loss per year for the cyan, magenta and yellow dyes (or silver, as all three).
    var rate: SIMD3<Float>
    /// Stain density per year in dye-equivalent units (cyan, magenta, yellow).
    var stain: SIMD3<Float>
    /// Light fading: extra proportional loss in thin dye (0 = density-independent).
    var thinBias: Float
    var years: Float

    static func of(_ stock: FilmStock, keeping: Keeping, years: Float, negative: Bool = false) -> Fade? {
        guard years > 0.25 else { return nil }
        let light = keeping == .framed && !negative
        var rate: SIMD3<Float>, stain: SIMD3<Float>
        switch (stock.kind, light) {
        case (.colorNegative, _) where negative:
            // Processed negatives in a shoebox: cyan dye weakest; the scanner zeroes on the (stained) base.
            rate = [0.006, 0.0018, 0.003]; stain = .zero
        case (.blackWhite, false):
            // Well-washed silver: very stable; slight warm yellowing of the gelatin and paper base.
            rate = SIMD3(repeating: 0.0004); stain = [0.0002, 0.0006, 0.0018]
        case (.blackWhite, true):
            rate = SIMD3(repeating: 0.0008); stain = [0.0001, 0.0003, 0.0010]
        case (.slide, false) where stock.id == "kodachrome64":
            rate = [0.0008, 0.0006, 0.0018]; stain = [0, 0.0001, 0.0004]
        case (.slide, false):
            rate = [0.006, 0.0015, 0.005]; stain = [0, 0.0003, 0.0015]
        case (.slide, true) where stock.id == "kodachrome64":
            rate = [0.007, 0.016, 0.011]; stain = .zero
        case (.slide, true):
            rate = [0.005, 0.010, 0.012]; stain = [0, 0.0001, 0.0004]
        case (_, false) where stock.medium == .cinePrint:
            // Pre-"low fade" Eastmancolor prints: cyan and yellow go, the famous pink reels.
            rate = [0.010, 0.002, 0.008]; stain = [0.0002, 0.0006, 0.0025]
        case (_, false):
            rate = [0.008, 0.0025, 0.004]; stain = [0.0003, 0.0008, 0.0035]
        case (_, true):
            rate = [0.004, 0.011, 0.013]; stain = [0, 0.0002, 0.0008]
        }
        return Fade(rate: rate, stain: stain, thinBias: light ? 0.8 : 0.1, years: min(years, 100))
    }

    /// Faded image dye densities.
    @inline(__always) func apply(_ d: SIMD3<Float>) -> SIMD3<Float> {
        var out = SIMD3<Float>()
        // Normalised so a density of 1.0 fades at the nominal rate.
        let ref = 1 + thinBias * exp(-1 / 0.4)
        for k in 0..<3 {
            let dk = max(d[k], 0)
            let f = (1 + thinBias * exp(-dk / 0.4)) / ref
            out[k] = dk * exp(-rate[k] * years * f)
        }
        // Stain grows almost linearly at first, then levels off as the couplers are used up.
        let st = stain * (60 * (1 - exp(-years / 60)))
        return out + st
    }

    /// B&W: faded silver density and the stain's colour (as a linear-light multiplier on the grey).
    @inline(__always) func silver(_ d: Float) -> Float { d * exp(-rate.x * years) }
    var silverTint: SIMD3<Float> {
        let st = stain * (60 * (1 - exp(-years / 60)))
        return SIMD3(pow(10, -st.x), pow(10, -st.y), pow(10, -st.z))
    }
}

extension FilmDiagnostics {
    /// Uniform-patch colours (8-bit sRGB) as the finished picture ages under `settings.keeping`.
    public static func fadeReport(_ stock: FilmStock, settings: DevelopSettings) -> String {
        let patches: [(String, SIMD3<Float>)] = [("white", [250, 250, 250]), ("grey", [128, 128, 128]), ("shadow", [40, 40, 40]),
                                                  ("skin", [194, 150, 130]), ("sky", [98, 122, 157]), ("leaf", [87, 108, 67])]
        var img = RGBImage(width: patches.count, height: 1)
        let toRec2020 = Spectral.xyzToRec2020.compose(Spectral.srgbToXYZ)
        for (i, p) in patches.enumerated() {
            let c = toRec2020.apply(SIMD3(FilmModel.srgbDecode(p.1.x / 255), FilmModel.srgbDecode(p.1.y / 255), FilmModel.srgbDecode(p.1.z / 255)))
            img.r[i] = c.x; img.g[i] = c.y; img.b[i] = c.z
        }
        var ctx = DevelopContext(fullLongSide: 3600, isDisplayReferred: true); ctx.uniform = true
        var s = "\(stock.id)  [\(settings.keeping.rawValue)\(settings.lab == .scan && stock.kind == .colorNegative ? ", scanned negative" : "")]\n"
        for years in [0, 15, 30, 50, 80] as [Float] {
            var s2 = settings; s2.printAge = years
            let o = Developer.develop(img, stock: stock, settings: s2, context: ctx)
            let row = patches.indices.map { i in
                String(format: "%@ %3.0f %3.0f %3.0f", patches[i].0, min(max(o.r[i], 0), 1) * 255,
                       min(max(o.g[i], 0), 1) * 255, min(max(o.b[i], 0), 1) * 255)
            }
            s += String(format: "  %2.0f y  ", years) + row.joined(separator: " | ") + "\n"
        }
        return s
    }
}

extension Keeping {
    /// Slider title for what is ageing: the print, the slide, or (for lab scans) the negative.
    public static func ageTitle(_ stock: FilmStock, scan: Bool) -> String {
        switch stock.kind {
        case .slide: "Slide age"
        case .colorNegative where scan: "Negative age"
        default: "Print age"
        }
    }
}
