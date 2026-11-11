import Foundation

public enum FilmKind: String, Codable, CaseIterable {
    case colorNegative = "Color Negative"
    case slide = "Color Slide"
    case blackWhite = "Black & White"
}

/// Print medium a negative is printed on (or the way a slide is viewed).
public enum PrintMedium: String, Codable {
    case endura          // Kodak colour paper
    case crystalArchive  // Fujifilm colour paper
    case cinePrint       // Kodak 2383-style motion-picture print film
    case bwPaper         // neutral silver gelatin paper
}

/// Hue sectors in Oklab hue degrees (used by the optional residual "lab" adjustment).
public enum HueSector: Int, CaseIterable {
    case red, orange, yellow, green, cyan, blue, magenta
    public var center: Float { [27, 58, 105, 142, 195, 262, 330][rawValue] }
    public var width: Float { [24, 18, 24, 30, 28, 30, 30][rawValue] }
}

/// A film stock, described physically.
///
/// **Spectral model.** Each dye-forming layer has a spectral sensitivity curve (from the shape of the
/// datasheet log-sensitivity plots), a characteristic curve, and a dye with its own absorption spectrum.
/// Light reaching the film is reconstructed spectrally from the photo, so colour separation, metamerism
/// and colour shifts under different light come from the same physics as on real film.
///
/// **Sources.** Peak wavelengths, curve gammas and RMS granularity follow manufacturer datasheets where
/// published (Kodak E-4040/E-4050/E-4046/F-4017/F-4018/H-1-2383, Fujifilm data sheets). Curve shapes are
/// fitted with a few Gaussian lobes rather than copied point-for-point, and colour-negative granularity
/// (Kodak publishes Print Grain Index, not RMS) is estimated, so treat this as a calibrated emulation.
public struct FilmStock: Identifiable, Hashable {
    public var id: String
    public var maker: String
    public var name: String
    public var iso: Int
    public var kind: FilmKind
    public var blurb: String

    // Spectral
    /// Spectral sensitivity of the red-, green- and blue-sensitive layers (B&W uses index 0 only).
    public var sensitivity: [[Lobe]] = []
    /// Fujifilm's 4th (cyan-sensitive) layer: inhibits the red layer, giving a negative red lobe near 510 nm.
    public var fourthLayer: Lobe? = nil
    /// Colour temperature the film is balanced for.
    public var balanceKelvin: Float = 5500
    /// Absorption spectra of the cyan, magenta and yellow image dyes (after masking).
    public var dyes: [[Lobe]] = []
    public var medium: PrintMedium = .endura
    /// Measured datasheet profile (spektrafilm, CC BY-SA 4.0) — when set it replaces the fitted spectra
    /// and curves above, and the stock's colour character comes from the data itself.
    public var measured: String? = nil
    public var isMeasured: Bool { measured.flatMap { MeasuredData.profile($0) } != nil }
    /// Measured characteristic curves for +1, +2… stops of push processing (developed longer).
    public var pushProfiles: [String] = []
    /// A slide emulsion developed in C-41 (see `crossProcessed`): no grey-scale neutralisation.
    public var isCrossProcessed = false

    // Reciprocity failure (Schwarzschild): beyond `reciprocityT0` seconds the film's effective exposure
    // grows as t^p instead of t. Per-layer p ≠ equal values give the colour shifts of long exposures.
    public var reciprocityT0: Float = 1
    public var reciprocityP: SIMD3<Float> = [0.85, 0.85, 0.85]

    // Tone
    public var contrast: Float = 0.6            // negative gamma, or reversal gamma for slides
    public var gammaRGB: SIMD3<Float> = [1, 1, 1]
    public var toe: Float = -1.7                // log exposure (rel. mid grey) of negative toe
    public var shoulder: Float = 2.8
    public var layerDmax: Float = 2.4           // max density above base for each layer
    public var paperContrast: Float = 2.45      // print paper slope at mid grey
    public var slideRange: Float = 3.4

    // DIR couplers (development-inhibitor-releasing)
    public var dirSame: Float = 0.08            // self-inhibition -> edge effects / local contrast
    public var dirInter: Float = 0.10           // interlayer inhibition -> colour saturation
    public var dirSpreadUm: Float = 15

    // Structure
    public var grainRMS: Float = 6               // diffuse RMS granularity ×1000 (48 µm aperture) at D = 1
    public var grainSizeUm: Float = 10           // dye-cloud / grain-clump size
    public var halationRGB: SIMD3<Float> = [0.012, 0.004, 0]
    public var halationRadiusUm: Float = 140
    public var softnessUm: Float = 5

    // Look targets. Saturation and per-hue character are *calibration targets*: the physical model's
    // layer crosstalk is fitted to reproduce them on a ColorChecker (see FilmModel.fitHueCalibration).
    // Shadow/highlight tints are applied as tonal crossovers.
    public var cast: SIMD3<Float> = [0, 0, 0]
    public var saturation: Float = 1
    public var hueShift: [Float] = Array(repeating: 0, count: 7)
    public var hueSat: [Float] = Array(repeating: 1, count: 7)
    public var hueLum: [Float] = Array(repeating: 0, count: 7)
    public var shadowTint: SIMD2<Float> = [0, 0]
    public var highlightTint: SIMD2<Float> = [0, 0]

    public var displayName: String { "\(maker) \(name)" }

    mutating func hue(_ s: HueSector, shift: Float = 0, sat: Float = 1, lum: Float = 0) {
        hueShift[s.rawValue] = shift; hueSat[s.rawValue] = sat; hueLum[s.rawValue] = lum
    }
    var hasResidual: Bool { shadowTint != .zero || highlightTint != .zero }

    /// The stock's documented colour character applied to a display-linear colour (Oklab hue sectors).
    func applyingLook(_ c: SIMD3<Float>) -> SIMD3<Float> {
        var img = RGBImage(width: 1, height: 1, r: [c.x], g: [c.y], b: [c.z])
        var s = self; s.shadowTint = .zero; s.highlightTint = .zero
        ColorFingerprint.apply(&img, stock: s)
        return SIMD3(img.r[0], img.g[0], img.b[0])
    }

    public static func == (a: FilmStock, b: FilmStock) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Spectral building blocks

enum Layers {
    /// R, G, B layer sensitivities from peak wavelength and half-widths.
    static func rgb(r: (Float, Float, Float), g: (Float, Float, Float), b: (Float, Float, Float)) -> [[Lobe]] {
        // Every silver-halide layer keeps a little native blue/UV sensitivity behind the yellow filter.
        // The green layer keeps a short-wave shoulder near 500 nm, as datasheet log-sensitivity plots show.
        [[Lobe(r.0, r.1, r.2), Lobe(440, 30, 30, 0.02)],
         [Lobe(g.0, g.1, g.2), Lobe(500, 18, 18, 0.5), Lobe(440, 30, 30, 0.03)],
         [Lobe(b.0, b.1, b.2), Lobe(400, 20, 30, 0.35)]]
    }
    static let kodakNegDyes: [[Lobe]] = [[Lobe(690, 62, 45)], [Lobe(552, 36, 40)], [Lobe(448, 30, 34)]]
    static let fujiNegDyes: [[Lobe]] = [[Lobe(682, 60, 45)], [Lobe(546, 36, 40)], [Lobe(446, 30, 34)]]
    static let ecnDyes: [[Lobe]] = [[Lobe(695, 62, 45)], [Lobe(552, 36, 40)], [Lobe(450, 30, 34)]]
    static let e6Dyes: [[Lobe]] = [[Lobe(655, 46, 40), Lobe(560, 30, 30, 0.06)],
                                   [Lobe(550, 32, 33), Lobe(440, 25, 25, 0.10)],
                                   [Lobe(445, 26, 30)]]
    static let velviaDyes: [[Lobe]] = [[Lobe(658, 42, 38), Lobe(560, 30, 30, 0.04)],
                                       [Lobe(548, 28, 30), Lobe(440, 25, 25, 0.07)],
                                       [Lobe(447, 24, 28)]]
    static let kodachromeDyes: [[Lobe]] = [[Lobe(645, 50, 42), Lobe(555, 30, 30, 0.08)],
                                           [Lobe(540, 34, 32), Lobe(440, 25, 25, 0.15)],
                                           [Lobe(440, 26, 28)]]
}

/// Print media: paper sensitivities, dyes, contrast and the enlarger lamp.
struct PrintProfile {
    let sensitivity: [[Lobe]]
    let dyes: [[Lobe]]
    let range: Float
    let base: Float
    let enlargerKelvin: Float
    var measured: MeasuredProfile? = nil

    var sensitivitySampled: [[Float]] { measured?.sensitivity ?? sensitivity.map { $0.sampled } }
    var dyesSampled: [[Float]] { measured?.dyes ?? dyes.map { $0.sampled } }
    var baseSpectrum: [Float] { measured?.base ?? [Float](repeating: base, count: Spectral.count) }
    var measuredRange: Float { measured.map { m in (0..<3).map { m.curves[$0].max() ?? 2 }.reduce(0, +) / 3 } ?? range }

    static let measuredIDs: [PrintMedium: String] = [.endura: "kodak_portra_endura",
                                                      .crystalArchive: "fujifilm_crystal_archive_typeii",
                                                      .cinePrint: "kodak_2383"]
    static func of(_ m: PrintMedium) -> PrintProfile {
        var p = fitted(m)
        if let id = measuredIDs[m], let data = MeasuredData.profiles[id] { p.measured = data }
        return p
    }

    static func fitted(_ m: PrintMedium) -> PrintProfile {
        switch m {
        case .endura:
            return PrintProfile(sensitivity: [[Lobe(695, 14, 14)], [Lobe(545, 14, 16)], [Lobe(465, 16, 16)]],
                                dyes: [[Lobe(650, 48, 40), Lobe(540, 30, 30, 0.10)],
                                       [Lobe(545, 32, 35), Lobe(440, 25, 25, 0.14)],
                                       [Lobe(445, 28, 30), Lobe(530, 25, 25, 0.04)]],
                                range: 2.3, base: 0.06, enlargerKelvin: 3200)
        case .crystalArchive:
            return PrintProfile(sensitivity: [[Lobe(690, 15, 14)], [Lobe(545, 14, 16)], [Lobe(460, 16, 16)]],
                                dyes: [[Lobe(660, 45, 40), Lobe(545, 30, 30, 0.12)],
                                       [Lobe(540, 32, 35), Lobe(440, 25, 25, 0.12)],
                                       [Lobe(440, 28, 30), Lobe(530, 25, 25, 0.04)]],
                                range: 2.3, base: 0.06, enlargerKelvin: 3200)
        case .cinePrint:
            return PrintProfile(sensitivity: [[Lobe(690, 15, 15)], [Lobe(545, 15, 15)], [Lobe(455, 18, 18)]],
                                dyes: [[Lobe(660, 45, 45), Lobe(550, 30, 30, 0.10)],
                                       [Lobe(550, 33, 33), Lobe(440, 25, 25, 0.15)],
                                       [Lobe(445, 28, 30)]],
                                range: 2.6, base: 0.05, enlargerKelvin: 3200)
        case .bwPaper:
            return PrintProfile(sensitivity: [], dyes: [], range: 2.1, base: 0.05, enlargerKelvin: 3200)
        }
    }
}

// MARK: - Catalogue

extension FilmStock {
    static func make(_ id: String, _ maker: String, _ name: String, iso: Int, _ kind: FilmKind,
                     _ blurb: String, _ configure: (inout FilmStock) -> Void) -> FilmStock {
        var s = FilmStock(id: id, maker: maker, name: name, iso: iso, kind: kind, blurb: blurb)
        switch kind {
        case .colorNegative:
            s.dyes = maker == "Fujifilm" ? Layers.fujiNegDyes : Layers.kodakNegDyes
            s.medium = maker == "Fujifilm" ? .crystalArchive : .endura
        case .slide:
            s.contrast = 1.75; s.dyes = Layers.e6Dyes; s.layerDmax = 3.4
            s.halationRGB = [0.008, 0.002, 0]; s.softnessUm = 4; s.dirSame = 0.06; s.dirInter = 0.12
        case .blackWhite:
            s.medium = .bwPaper; s.paperContrast = 2.1; s.layerDmax = 2.6
            s.halationRGB = [0.006, 0, 0]; s.dirInter = 0; s.dirSame = 0.12; s.dirSpreadUm = 30
        }
        let defaultHalation = s.halationRGB
        configure(&s)
        // Datasheet antihalation rating: consumer stocks with a weak antihalation layer let more light
        // bounce back from the base, so their glow around highlights is stronger (unless set explicitly).
        if s.halationRGB == defaultHalation, let id = s.measured, MeasuredData.profiles[id]?.antihalation == "weak" {
            s.halationRGB *= Self.weakAntihalationFactor
        }
        return s
    }
    static let weakAntihalationFactor: Float = 2.5

    public static func stock(id: String) -> FilmStock? { catalog.first { $0.id == id } }

    public static let catalog: [FilmStock] = [
        // MARK: Kodak colour negative
        make("portra160", "Kodak", "Portra 160", iso: 160, .colorNegative,
             "Very fine grain, low contrast, gentle pastel colour and natural skin.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.86, 0.86, 0.84]
            s.measured = "kodak_portra_160"
            s.saturation = 0.9
            s.hue(.red, shift: 1, sat: 0.95); s.hue(.orange, shift: 2, sat: 1.04); s.hue(.yellow, shift: -4, sat: 0.9)
            s.hue(.green, shift: -6, sat: 0.85); s.hue(.cyan, sat: 0.92); s.hue(.blue, shift: -6, sat: 0.9); s.hue(.magenta, sat: 0.92)
            s.shadowTint = [-0.003, -0.003]; s.highlightTint = [0.003, 0.006]
            s.sensitivity = Layers.rgb(r: (645, 26, 22), g: (550, 30, 26), b: (445, 28, 26))
            s.contrast = 0.55; s.paperContrast = 2.4; s.dirInter = 0.08
            s.cast = [0.008, 0.002, -0.006]
            s.grainRMS = 4.0; s.grainSizeUm = 8; s.softnessUm = 5
        },
        make("portra400", "Kodak", "Portra 400", iso: 400, .colorNegative,
             "The portrait standard: warm skin, soft muted greens, huge overexposure latitude.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.86, 0.86, 0.84]
            s.measured = "kodak_portra_400"
            s.saturation = 0.95
            s.hue(.red, shift: 2, sat: 0.98); s.hue(.orange, shift: 3, sat: 1.06); s.hue(.yellow, shift: -3, sat: 0.95)
            s.hue(.green, shift: -8, sat: 0.82); s.hue(.cyan, sat: 0.92); s.hue(.blue, shift: -8, sat: 0.9); s.hue(.magenta, sat: 0.9)
            s.shadowTint = [-0.004, -0.003]; s.highlightTint = [0.004, 0.007]
            s.sensitivity = Layers.rgb(r: (645, 25, 22), g: (550, 30, 26), b: (445, 28, 26))
            s.contrast = 0.58; s.dirInter = 0.09
            s.cast = [0.010, 0.003, -0.008]
            s.grainRMS = 5.5; s.grainSizeUm = 11; s.softnessUm = 6
        },
        make("portra800", "Kodak", "Portra 800", iso: 800, .colorNegative,
             "Warmer and punchier than 400, visible grain, rich reds in low light.") { s in
            s.pushProfiles = ["kodak_portra_800_push1", "kodak_portra_800_push2"]
            s.reciprocityT0 = 1; s.reciprocityP = [0.85, 0.85, 0.83]
            s.measured = "kodak_portra_800"
            s.saturation = 1.0
            s.hue(.red, shift: 3, sat: 1.05); s.hue(.orange, shift: 3, sat: 1.08); s.hue(.yellow, shift: -4, sat: 0.96)
            s.hue(.green, shift: -8, sat: 0.85); s.hue(.blue, shift: -6, sat: 0.95)
            s.shadowTint = [-0.005, -0.002]; s.highlightTint = [0.004, 0.008]
            s.sensitivity = Layers.rgb(r: (648, 25, 22), g: (550, 30, 26), b: (445, 28, 26))
            s.contrast = 0.62; s.dirInter = 0.11
            s.cast = [0.014, 0.004, -0.012]
            s.grainRMS = 7.0; s.grainSizeUm = 14; s.softnessUm = 7
        },
        make("ektar100", "Kodak", "Ektar 100", iso: 100, .colorNegative,
             "Finest-grain colour negative. Saturated reds and deep blues, slide-like punch.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.83, 0.83, 0.81]
            s.measured = "kodak_ektar_100"
            s.saturation = 1.18
            s.hue(.red, shift: -2, sat: 1.2); s.hue(.orange, sat: 1.08); s.hue(.yellow, sat: 1.05); s.hue(.green, shift: -2, sat: 1.05)
            s.hue(.cyan, sat: 1.1); s.hue(.blue, shift: 2, sat: 1.2); s.hue(.magenta, sat: 1.1)
            s.sensitivity = Layers.rgb(r: (652, 20, 18), g: (548, 24, 22), b: (445, 24, 22))
            s.contrast = 0.70; s.dirInter = 0.17; s.dirSame = 0.10
            s.grainRMS = 3.5; s.grainSizeUm = 6; s.softnessUm = 4
        },
        make("gold200", "Kodak", "Gold 200", iso: 200, .colorNegative,
             "Consumer classic. Golden warmth, sunny yellows, nostalgic summer look.") { s in
            s.reciprocityT0 = 0.5; s.reciprocityP = [0.8, 0.8, 0.78]
            s.measured = "kodak_gold_200"
            s.saturation = 1.06
            s.hue(.red, sat: 1.05); s.hue(.orange, shift: 2, sat: 1.08); s.hue(.yellow, shift: -4, sat: 1.15)
            s.hue(.green, shift: -10, sat: 0.9); s.hue(.cyan, sat: 0.9); s.hue(.blue, shift: -4, sat: 0.95)
            s.highlightTint = [0.004, 0.010]
            s.sensitivity = Layers.rgb(r: (640, 30, 25), g: (552, 32, 28), b: (440, 30, 28))
            s.contrast = 0.64; s.dirInter = 0.10
            s.cast = [0.016, 0.010, -0.018]
            s.grainRMS = 5.0; s.grainSizeUm = 10; s.softnessUm = 6
        },
        make("ultramax400", "Kodak", "UltraMax 400", iso: 400, .colorNegative,
             "Contrasty, saturated consumer film. Warm, bold reds, everyday snapshot feel.") { s in
            s.reciprocityT0 = 0.5; s.reciprocityP = [0.8, 0.8, 0.78]
            s.measured = "kodak_ultramax_400"
            s.saturation = 1.1
            s.hue(.red, shift: 2, sat: 1.12); s.hue(.orange, sat: 1.05); s.hue(.yellow, shift: -3, sat: 1.1)
            s.hue(.green, shift: -8, sat: 0.95); s.hue(.blue, shift: -2, sat: 1.05)
            s.highlightTint = [0.004, 0.008]
            s.sensitivity = Layers.rgb(r: (642, 28, 24), g: (550, 31, 27), b: (442, 30, 27))
            s.contrast = 0.67; s.paperContrast = 2.5; s.dirInter = 0.13
            s.cast = [0.014, 0.006, -0.012]
            s.grainRMS = 6.5; s.grainSizeUm = 13; s.softnessUm = 7
        },
        make("colorplus200", "Kodak", "ColorPlus 200", iso: 200, .colorNegative,
             "Budget film: warm, slightly soft, yellow-red bias, muted greens.") { s in
            s.reciprocityT0 = 0.5; s.reciprocityP = [0.78, 0.78, 0.76]
            s.saturation = 0.98
            s.hue(.red, sat: 1.02); s.hue(.orange, shift: 2, sat: 1.05); s.hue(.yellow, shift: -5, sat: 1.05)
            s.hue(.green, shift: -12, sat: 0.82); s.hue(.cyan, sat: 0.85); s.hue(.blue, shift: -6, sat: 0.88)
            s.shadowTint = [0.003, 0.004]; s.highlightTint = [0.005, 0.010]
            s.sensitivity = Layers.rgb(r: (638, 32, 26), g: (552, 34, 30), b: (440, 32, 30))
            s.contrast = 0.62; s.dirInter = 0.07
            s.cast = [0.018, 0.008, -0.018]
            s.grainRMS = 6.0; s.grainSizeUm = 12; s.softnessUm = 8
        },
        make("vision250d", "Kodak", "Vision3 250D", iso: 250, .colorNegative,
             "Motion-picture negative printed to cinema print film: teal shadows, warm highlights.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.85, 0.85, 0.85]
            s.measured = "kodak_vision3_250d"
            s.saturation = 0.95
            s.hue(.red, sat: 1.05); s.hue(.orange, shift: 1, sat: 1.03); s.hue(.yellow, shift: -4, sat: 0.92)
            s.hue(.green, shift: -6, sat: 0.85); s.hue(.cyan, shift: -4); s.hue(.blue, shift: -8, sat: 0.92)
            s.shadowTint = [-0.008, -0.007]; s.highlightTint = [0.004, 0.008]
            s.sensitivity = Layers.rgb(r: (655, 22, 22), g: (548, 25, 24), b: (445, 25, 25))
            s.dyes = Layers.ecnDyes; s.medium = .cinePrint
            s.contrast = 0.58; s.paperContrast = 2.9; s.dirInter = 0.12
            s.halationRGB = [0, 0, 0]       // remjet anti-halation backing
            s.grainRMS = 5.0; s.grainSizeUm = 10; s.softnessUm = 5
        },
        // MARK: Fujifilm colour negative
        make("pro400h", "Fujifilm", "Pro 400H", iso: 400, .colorNegative,
             "Airy, cool pastel palette. Clean cyan-leaning greens, pale pink skin. Has Fuji's 4th colour layer.") { s in
            s.reciprocityT0 = 2; s.reciprocityP = [0.9, 0.89, 0.9]
            s.measured = "fujifilm_pro_400h"
            s.saturation = 0.9
            s.hue(.red, shift: -3, sat: 0.95); s.hue(.orange, shift: -3, sat: 0.92); s.hue(.yellow, shift: -2, sat: 0.9)
            s.hue(.green, shift: 10, sat: 0.95); s.hue(.cyan, sat: 1.02); s.hue(.blue, shift: -4, sat: 0.92); s.hue(.magenta, sat: 0.95)
            s.shadowTint = [-0.004, -0.004]; s.highlightTint = [-0.002, 0.003]
            s.sensitivity = Layers.rgb(r: (645, 24, 22), g: (540, 27, 26), b: (445, 26, 26))
            s.fourthLayer = Lobe(512, 18, 18, 0.28)
            s.contrast = 0.56; s.paperContrast = 2.35; s.dirInter = 0.09
            s.cast = [-0.004, 0.004, 0.004]
            s.grainRMS = 5.5; s.grainSizeUm = 11; s.softnessUm = 6
        },
        make("superia400", "Fujifilm", "Superia X-TRA 400", iso: 400, .colorNegative,
             "Punchy consumer Fuji. Green bias, magenta-leaning reds, greenish shadows.") { s in
            s.reciprocityT0 = 2; s.reciprocityP = [0.86, 0.84, 0.86]
            s.measured = "fujifilm_xtra_400"
            s.saturation = 1.1
            s.hue(.red, shift: -3, sat: 1.1); s.hue(.yellow, shift: 2, sat: 1.05); s.hue(.green, shift: 4, sat: 1.12)
            s.hue(.cyan, sat: 1.05); s.hue(.blue, shift: 2, sat: 1.08); s.hue(.magenta, sat: 1.05)
            s.shadowTint = [-0.007, 0.001]
            s.sensitivity = Layers.rgb(r: (640, 26, 24), g: (540, 28, 26), b: (445, 28, 26))
            s.fourthLayer = Lobe(510, 18, 18, 0.32)
            s.contrast = 0.66; s.paperContrast = 2.5; s.dirInter = 0.13; s.gammaRGB = [1.0, 0.97, 1.0]
            s.cast = [-0.004, 0.010, -0.004]
            s.grainRMS = 6.5; s.grainSizeUm = 13; s.softnessUm = 7
        },
        make("c200", "Fujifilm", "Fujicolor C200", iso: 200, .colorNegative,
             "Cool, fresh everyday film. Clear blues and cyans, slight green tint.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.84, 0.82, 0.84]
            s.measured = "fujifilm_c200"
            s.saturation = 1.0
            s.hue(.red, shift: -2); s.hue(.orange, sat: 0.98); s.hue(.green, shift: 6, sat: 1.05)
            s.hue(.cyan, sat: 1.08); s.hue(.blue, shift: -3, sat: 1.05)
            s.shadowTint = [-0.005, -0.001]
            s.sensitivity = Layers.rgb(r: (640, 26, 24), g: (545, 28, 26), b: (445, 28, 26))
            s.fourthLayer = Lobe(510, 18, 18, 0.20)
            s.contrast = 0.63; s.dirInter = 0.10
            s.cast = [-0.006, 0.008, 0.004]
            s.grainRMS = 5.5; s.grainSizeUm = 11; s.softnessUm = 6
        },
        // MARK: CineStill
        make("cinestill800t", "CineStill", "800T", iso: 800, .colorNegative,
             "Tungsten cinema stock without remjet: red halos around lights, cool cast in daylight.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.84, 0.85, 0.85]
            s.measured = "kodak_vision3_500t"
            s.saturation = 1.0
            s.hue(.red, shift: 4, sat: 1.08); s.hue(.yellow, shift: -6, sat: 0.9); s.hue(.green, shift: -6, sat: 0.85)
            s.hue(.cyan, sat: 1.05); s.hue(.blue, shift: -6)
            s.shadowTint = [-0.008, -0.008]; s.highlightTint = [0.005, 0.004]
            s.sensitivity = Layers.rgb(r: (655, 22, 22), g: (548, 25, 24), b: (445, 25, 25))
            s.dyes = Layers.ecnDyes; s.medium = .cinePrint; s.balanceKelvin = 3200
            s.contrast = 0.60; s.paperContrast = 2.8; s.dirInter = 0.11
            s.grainRMS = 7.5; s.grainSizeUm = 15; s.softnessUm = 7
            s.halationRGB = [0.22, 0.05, 0]; s.halationRadiusUm = 200
        },
        // MARK: Slide
        make("e100", "Kodak", "Ektachrome E100", iso: 100, .slide,
             "Modern Kodak slide film. Clean, neutral-cool, accurate blues, crisp.") { s in
            s.reciprocityT0 = 10; s.reciprocityP = [0.9, 0.9, 0.88]
            s.measured = "kodak_ektachrome_100"
            s.saturation = 1.08
            s.hue(.red, sat: 1.05); s.hue(.yellow, sat: 0.98); s.hue(.green, sat: 1.02); s.hue(.cyan, sat: 1.08); s.hue(.blue, sat: 1.1)
            s.sensitivity = Layers.rgb(r: (650, 24, 22), g: (545, 25, 25), b: (450, 26, 26))
            s.contrast = 1.7; s.slideRange = 3.5; s.cast = [-0.004, 0, 0.006]
            s.grainRMS = 8; s.grainSizeUm = 7
        },
        make("kodachrome64", "Kodak", "Kodachrome 64", iso: 64, .slide,
             "The legendary K-14 look: deep reds, warm yellows, dense shadows, olive greens.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.8, 0.8, 0.76]
            s.measured = "kodak_kodachrome_64"
            s.saturation = 1.12
            s.hue(.red, shift: 2, sat: 1.18); s.hue(.orange, sat: 1.08); s.hue(.yellow, shift: -4, sat: 1.12)
            s.hue(.green, shift: -8, sat: 0.92); s.hue(.cyan, sat: 0.95); s.hue(.blue, shift: -6, sat: 1.12); s.hue(.magenta, sat: 0.95)
            s.shadowTint = [0.004, 0.006]
            s.sensitivity = Layers.rgb(r: (640, 28, 24), g: (545, 26, 25), b: (445, 28, 24))
            s.dyes = Layers.kodachromeDyes
            s.contrast = 1.85; s.slideRange = 3.6; s.gammaRGB = [1.0, 1.02, 1.04]; s.dirInter = 0.14
            s.cast = [0.010, 0.004, -0.008]
            s.grainRMS = 10; s.grainSizeUm = 9
        },
        make("velvia50", "Fujifilm", "Velvia 100", iso: 100, .slide,
             "Landscape icon. Extreme saturation, electric greens and blues, magenta shadows.") { s in
            s.reciprocityT0 = 8; s.reciprocityP = [0.88, 0.86, 0.88]
            s.measured = "fujifilm_velvia_100"
            s.saturation = 1.32
            s.hue(.red, shift: -4, sat: 1.2); s.hue(.orange, sat: 1.1); s.hue(.yellow, sat: 1.15); s.hue(.green, shift: -4, sat: 1.35)
            s.hue(.cyan, sat: 1.25); s.hue(.blue, shift: 4, sat: 1.3); s.hue(.magenta, sat: 1.2)
            s.sensitivity = Layers.rgb(r: (645, 20, 18), g: (542, 22, 22), b: (448, 22, 22))
            s.dyes = Layers.velviaDyes
            s.contrast = 2.0; s.slideRange = 3.7; s.dirInter = 0.15; s.dirSame = 0.08
            s.grainRMS = 9; s.grainSizeUm = 6; s.softnessUm = 3.5
        },
        make("provia100f", "Fujifilm", "Provia 100F", iso: 100, .slide,
             "Fuji's neutral reference slide: faithful colour, moderate saturation, fine grain.") { s in
            s.reciprocityT0 = 128; s.reciprocityP = [0.9, 0.9, 0.9]
            s.measured = "fujifilm_provia_100f"
            s.saturation = 1.1
            s.hue(.red, sat: 1.05); s.hue(.green, sat: 1.06); s.hue(.cyan, sat: 1.05); s.hue(.blue, sat: 1.08)
            s.sensitivity = Layers.rgb(r: (645, 23, 22), g: (545, 25, 24), b: (448, 25, 25))
            s.contrast = 1.75; s.slideRange = 3.5
            s.grainRMS = 8; s.grainSizeUm = 7
        },
        make("astia100f", "Fujifilm", "Astia 100F", iso: 100, .slide,
             "Soft-contrast portrait slide. Smooth skin, restrained saturation, clear blues.") { s in
            s.reciprocityT0 = 4; s.reciprocityP = [0.88, 0.88, 0.87]
            s.saturation = 1.03
            s.hue(.green, sat: 1.02); s.hue(.blue, sat: 1.06)
            s.highlightTint = [0.002, 0.003]
            s.sensitivity = Layers.rgb(r: (645, 25, 22), g: (545, 27, 26), b: (448, 27, 26))
            s.contrast = 1.55; s.slideRange = 3.4; s.dirInter = 0.08
            s.grainRMS = 7; s.grainSizeUm = 7; s.softnessUm = 4.5
        },
        // MARK: Black & white (panchromatic sensitivity shapes from datasheet spectrograms)
        make("trix400", "Kodak", "Tri-X 400", iso: 400, .blackWhite,
             "Photojournalism classic. Gritty, punchy grain, deep blacks, edge bite.") { s in
            s.reciprocityT0 = 0.1; s.reciprocityP = [0.7, 0.7, 0.7]
            s.sensitivity = [[Lobe(420, 40, 40, 0.9), Lobe(555, 40, 40, 1.0), Lobe(620, 35, 22, 0.9)]]
            s.contrast = 0.66; s.paperContrast = 2.15; s.toe = -1.5
            s.grainRMS = 17; s.grainSizeUm = 15; s.dirSame = 0.2; s.softnessUm = 6
        },
        make("tmax100", "Kodak", "T-Max 100", iso: 100, .blackWhite,
             "Tabular-grain precision. Very fine grain, smooth tones, extended red sensitivity.") { s in
            s.reciprocityT0 = 0.3; s.reciprocityP = [0.86, 0.86, 0.86]
            s.sensitivity = [[Lobe(420, 40, 40, 0.9), Lobe(550, 40, 40, 1.0), Lobe(635, 40, 28, 0.95)]]
            s.contrast = 0.64
            s.grainRMS = 8; s.grainSizeUm = 7; s.dirSame = 0.1; s.softnessUm = 4
        },
        make("hp5", "Ilford", "HP5 Plus", iso: 400, .blackWhite,
             "Forgiving, softer-contrast 400 with a classic, organic grain.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.76, 0.76, 0.76]
            s.sensitivity = [[Lobe(425, 40, 40, 0.9), Lobe(550, 40, 40, 1.0), Lobe(615, 35, 22, 0.85)]]
            s.contrast = 0.60
            s.grainRMS = 16; s.grainSizeUm = 17; s.dirSame = 0.15; s.softnessUm = 6
        },
        make("fp4", "Ilford", "FP4 Plus", iso: 125, .blackWhite,
             "Traditional medium-speed film: fine grain, rich mid-tones, gentle contrast.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.68, 0.68, 0.68]
            s.sensitivity = [[Lobe(425, 40, 40, 0.9), Lobe(550, 40, 40, 1.0), Lobe(615, 35, 22, 0.85)]]
            s.contrast = 0.62
            s.grainRMS = 10; s.grainSizeUm = 9; s.dirSame = 0.15; s.softnessUm = 5
        },
        make("delta3200", "Ilford", "Delta 3200", iso: 3200, .blackWhite,
             "Low-light monster. Big, soft grain, flat shadows, moody night look.") { s in
            s.reciprocityT0 = 1; s.reciprocityP = [0.75, 0.75, 0.75]
            s.sensitivity = [[Lobe(425, 40, 40, 0.9), Lobe(550, 40, 40, 1.0), Lobe(625, 35, 24, 0.95)]]
            s.contrast = 0.55; s.toe = -1.2
            s.grainRMS = 24; s.grainSizeUm = 26; s.dirSame = 0.1; s.softnessUm = 8
        },
        make("acros100", "Fujifilm", "Neopan Acros 100 II", iso: 100, .blackWhite,
             "Ortho-panchromatic: darker reds, luminous skies, ultra-fine grain, rich blacks.") { s in
            s.reciprocityT0 = 120; s.reciprocityP = [0.85, 0.85, 0.85]
            s.sensitivity = [[Lobe(430, 40, 40, 1.0), Lobe(540, 40, 38, 1.0), Lobe(598, 30, 18, 0.55)]]
            s.contrast = 0.67; s.paperContrast = 2.15
            s.grainRMS = 7; s.grainSizeUm = 6; s.dirSame = 0.12; s.softnessUm = 3.5
        },
    ]
}
