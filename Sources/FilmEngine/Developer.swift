import Foundation
import Accelerate
import simd

public enum FilmFormat: String, CaseIterable, Codable, Identifiable {
    case halfFrame, mm35, mf645, mf66, mf67, lf45
    public var id: String { rawValue }
    /// Long side of the frame in millimetres — sets grain size relative to the picture.
    public var longSideMM: Float {
        switch self { case .halfFrame: 24; case .mm35: 36; case .mf645: 56; case .mf66: 56; case .mf67: 70; case .lf45: 120 }
    }
    public var label: String {
        switch self {
        case .halfFrame: "Half frame (18×24)"; case .mm35: "35mm"; case .mf645: "120 · 6×4.5"; case .mf66: "120 · 6×6"
        case .mf67: "120 · 6×7"; case .lf45: "Large format 4×5"
        }
    }
    /// Roll or sheet film (for borders): 35 mm / half frame have sprocket holes.
    public var hasSprockets: Bool { self == .halfFrame || self == .mm35 }
}

/// Print paper surface: how much light reflects off the surface before reaching the image, which sets
/// how deep the blacks can be (glossy ≈ D-max 2.3, lustre ≈ 2.0, matte ≈ 1.6).
public enum PaperSurface: String, CaseIterable, Codable, Identifiable {
    case glossy, lustre, matte
    public var id: String { rawValue }
    public var label: String { switch self { case .glossy: "Glossy"; case .lustre: "Lustre"; case .matte: "Matte" } }
    var flare: Float { switch self { case .glossy: 0.004; case .lustre: 0.010; case .matte: 0.025 } }
}

/// Frame border on the developed picture.
public enum FilmBorder: String, CaseIterable, Codable, Identifiable {
    case none, filed, fullFrame
    public var id: String { rawValue }
    public var label: String { switch self { case .none: "None"; case .filed: "Filed carrier"; case .fullFrame: "Full-frame scan" } }
}

public struct DevelopSettings: Codable, Equatable {
    /// Exposure error in stops (over/under-exposing the film; the lab still prints a normal density).
    public var exposure: Float = 0
    /// Push (+) / pull (−) processing in stops: rated speed change with compensating development.
    public var push: Float = 0
    /// Grain multiplier (1 = calibrated to the datasheet).
    public var grain: Float = 1
    /// Halation multiplier (1 = stock default).
    public var halation: Float = 1
    public var format: FilmFormat = .mm35
    /// Let the film see the real scene light (from the RAW's white balance) instead of a neutralised image.
    public var sceneLight: Bool = true
    /// How much of the scene-light colour cast the lab/scanner removes (0 = none, 1 = all).
    public var labCorrection: Float = 0.7
    /// Apply the film's reciprocity failure for long shutter speeds (from EXIF).
    public var reciprocity: Bool = true
    /// Colour negatives: optical print or lab scan.
    public var lab: LabProcess = .print
    /// Development agitation (datasheets assume continuous).
    public var agitation: Agitation = .continuous
    /// Expired film: years past date, and how it was stored.
    public var ageYears: Float = 0
    public var storage: Storage = .room
    /// Filter on the lens.
    public var filter: LensFilter = .none
    /// Slide film developed in C-41.
    public var crossProcess = false
    /// Colour negative loaded backwards.
    public var redscale = false
    /// Printing: enlarger filtration in CC units (yellow, magenta), print exposure in stops, pre-flash (0…1).
    public var ccYellow: Float = 0
    public var ccMagenta: Float = 0
    public var printExposure: Float = 0
    public var preflash: Float = 0
    /// B&W variable-contrast paper grade (−1 = "00" … 5); 2 ≈ unfiltered.
    public var paperGrade: Float = 2
    public var paperSurface: PaperSurface = .glossy
    public var border: FilmBorder = .none
    /// Years the finished print / slide (or, for scans, the negative) has been kept, and how.
    public var printAge: Float = 0
    public var keeping: Keeping = .album
    public init() {}

    // Tolerant decoding: settings saved by older versions keep working when fields are added.
    enum CodingKeys: String, CodingKey { case exposure, push, grain, halation, format, sceneLight, labCorrection, reciprocity, lab, agitation, ageYears, storage, filter, crossProcess, redscale, ccYellow, ccMagenta, printExposure, preflash, paperGrade, paperSurface, border, printAge, keeping }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Float.self, forKey: .exposure) ?? 0
        push = try c.decodeIfPresent(Float.self, forKey: .push) ?? 0
        grain = try c.decodeIfPresent(Float.self, forKey: .grain) ?? 1
        halation = try c.decodeIfPresent(Float.self, forKey: .halation) ?? 1
        format = try c.decodeIfPresent(FilmFormat.self, forKey: .format) ?? .mm35
        sceneLight = try c.decodeIfPresent(Bool.self, forKey: .sceneLight) ?? true
        labCorrection = try c.decodeIfPresent(Float.self, forKey: .labCorrection) ?? 0.7
        reciprocity = try c.decodeIfPresent(Bool.self, forKey: .reciprocity) ?? true
        lab = try c.decodeIfPresent(LabProcess.self, forKey: .lab) ?? .print
        agitation = try c.decodeIfPresent(Agitation.self, forKey: .agitation) ?? .continuous
        ageYears = try c.decodeIfPresent(Float.self, forKey: .ageYears) ?? 0
        storage = try c.decodeIfPresent(Storage.self, forKey: .storage) ?? .room
        filter = try c.decodeIfPresent(LensFilter.self, forKey: .filter) ?? .none
        crossProcess = try c.decodeIfPresent(Bool.self, forKey: .crossProcess) ?? false
        redscale = try c.decodeIfPresent(Bool.self, forKey: .redscale) ?? false
        ccYellow = try c.decodeIfPresent(Float.self, forKey: .ccYellow) ?? 0
        ccMagenta = try c.decodeIfPresent(Float.self, forKey: .ccMagenta) ?? 0
        printExposure = try c.decodeIfPresent(Float.self, forKey: .printExposure) ?? 0
        preflash = try c.decodeIfPresent(Float.self, forKey: .preflash) ?? 0
        paperGrade = try c.decodeIfPresent(Float.self, forKey: .paperGrade) ?? 2
        paperSurface = try c.decodeIfPresent(PaperSurface.self, forKey: .paperSurface) ?? .glossy
        border = try c.decodeIfPresent(FilmBorder.self, forKey: .border) ?? .none
        printAge = try c.decodeIfPresent(Float.self, forKey: .printAge) ?? 0
        keeping = try c.decodeIfPresent(Keeping.self, forKey: .keeping) ?? .album
    }
}

/// Geometry and capture data for the buffer being developed.
public struct DevelopContext {
    /// Long side, in pixels, of the *whole* photo at the scale of this buffer.
    public var fullLongSide: Int
    public var originX: Int = 0
    public var originY: Int = 0
    public var seed: UInt32 = 1
    /// Camera JPEGs are already tone-mapped; we approximately undo that.
    public var isDisplayReferred: Bool = false
    /// Correlated colour temperature of the scene light (as shot), when known from RAW metadata.
    public var sceneKelvin: Float? = nil
    /// Sensor clipping level in the linear buffer (for halation from blown highlights).
    public var clipLevel: Float? = nil
    /// Shutter speed in seconds (EXIF), for reciprocity failure.
    public var exposureTime: Double? = nil
    /// Treat every pixel as a large uniform area: no scatter, halation, grain or sharpening, and the
    /// uniform-area result of the spatial chemistry (DIR, exhaustion). Used to build colour LUTs.
    public var uniform = false

    public init(fullLongSide: Int, originX: Int = 0, originY: Int = 0, seed: UInt32 = 1,
                isDisplayReferred: Bool = false, sceneKelvin: Float? = nil, clipLevel: Float? = nil) {
        self.fullLongSide = fullLongSide; self.originX = originX; self.originY = originY
        self.seed = seed; self.isDisplayReferred = isDisplayReferred
        self.sceneKelvin = sceneKelvin; self.clipLevel = clipLevel
    }
}

extension DevelopContext {
    public func with(_ f: (inout DevelopContext) -> Void) -> DevelopContext { var c = self; f(&c); return c }
}

public enum Developer {
    /// Allowance for scanner/print MTF, which softens visible grain relative to a microdensitometer.
    static let grainCalibration: Float = 0.6
    static let midGrey: Float = 0.18
    static let midGreyDensity: Float = 0.745   // -log10(0.18)

    @inline(__always) static func logistic(_ x: Float) -> Float { 1 / (1 + exp(-x)) }
    @inline(__always) static func logit(_ p: Float) -> Float { log(p / (1 - p)) }
    @inline(__always) static func softplus(_ u: Float, _ k: Float) -> Float {
        let ku = k * u
        return ku > 20 ? u : log1p(exp(ku)) / k
    }
    @inline(__always) static func negCurve(_ x: Float, gamma: Float, toe: Float, shoulder: Float) -> Float {
        gamma * (softplus(x - toe, 3.2) - softplus(x - shoulder, 2.2))
    }
    @inline(__always) static func softClip(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        lo + softplus(x - lo, 3) - softplus(x - hi, 3)
    }
    @inline(__always) static func srgbEncode(_ v: Float) -> Float {
        let x = min(max(v, 0), 1)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }
    /// sRGB transfer function (for showing undeveloped originals).
    public static func encode(_ v: Float) -> Float { srgbEncode(v) }

    /// Develops a scene-linear image (linear Rec.2020 primaries) into a display-ready sRGB film rendering.
    public static func develop(_ img: RGBImage, stock filmStock: FilmStock, settings: DevelopSettings, context: DevelopContext) -> RGBImage {
        let stock = settings.crossProcess ? (filmStock.crossProcessed ?? filmStock) : filmStock
        let w = img.width, h = img.height
        let pixelUm = settings.format.longSideMM * 1000 / Float(max(1, context.fullLongSide))
        let model = FilmModel.model(for: stock)
        let tone = model.tone(push: settings.push, aging: Aging(years: settings.ageYears, storage: settings.storage, iso: stock.iso))
        let kelvin = settings.sceneLight ? context.sceneKelvin : nil
        let redscale = settings.redscale && stock.kind == .colorNegative
        var table = model.table(kelvin: kelvin, filter: settings.filter, redscale: redscale)
        // Rated speed: pushing N stops means the film received N stops less light.
        let filmEV = settings.exposure - settings.push
        // Reciprocity failure: per-layer effective exposure (t/t0)^(p-1) beyond t0.
        var reciprocityEV: Float = 0
        if settings.reciprocity, let t = context.exposureTime, Float(t) > stock.reciprocityT0 {
            let ratio = Float(t) / stock.reciprocityT0
            let g = SIMD3(pow(ratio, stock.reciprocityP.x - 1), pow(ratio, stock.reciprocityP.y - 1), pow(ratio, stock.reciprocityP.z - 1))
            table = table.applying(Spectral.M3(r0: [g.x, 0, 0], r1: [0, g.y, 0], r2: [0, 0, g.z]))
            reciprocityEV = log2((g.x + g.y + g.z) / 3)
        }
        let neutral = model.cachedNeutralizer(push: settings.push)
        // A redscale cast is far outside a printer's colour-correction range: it can only take the edge off.
        let correction = redscale ? min(settings.labCorrection, 0.3) : settings.labCorrection
        var balance = model.balance(scene: table, tone: tone, ev: filmEV, correction: correction, neutral: neutral,
                                    densityEV: reciprocityEV)
        let scanner = stock.kind == .colorNegative && settings.lab == .scan ? model.scanModel(push: settings.push) : nil
        // Archival fading of the finished print / slide (or, for a scan, of the stored negative).
        let fade = Fade.of(stock, keeping: settings.keeping, years: settings.printAge, negative: scanner != nil)
        var scanBal = scanner.map { model.scanBalance($0, scene: table, tone: tone, ev: filmEV, correction: correction,
                                                       densityEV: reciprocityEV, fade: fade) } ?? .zero
        // The printer's own hand: dichroic filtration (+Y removes blue light from the enlarger → a bluer
        // print; +M → a greener print) and print exposure (+1 stop → a darker print). On a scan the same
        // controls shift the scanner's channel levels the same visual way.
        let cc = SIMD3<Float>(0, settings.ccMagenta, settings.ccYellow) * 0.01
        if stock.kind == .colorNegative {
            balance += -cc + SIMD3(repeating: settings.printExposure * log10(2))
            scanBal += cc * 0.55 - SIMD3(repeating: settings.printExposure * 0.16)
        }
        // B&W: variable-contrast paper; grade filter plus any colour-head filtration set the contrast.
        var bwKp: Float = 0
        if stock.kind == .blackWhite {
            bwKp = model.bwPaperKp(grade: settings.paperGrade, ccY: settings.ccYellow, ccM: settings.ccMagenta)
            // keep mid grey on its density: balance = z(kp) + grey density
            let fm = Developer.logit(Developer.midGreyDensity / model.printRange)
            balance += SIMD3(repeating: fm / bwKp - fm / model.paperKp + settings.printExposure * log10(2))
        }
        let flash = stock.kind == .slide ? 0 : settings.preflash * 0.06
        // The printer re-sets exposure after flashing so mid grey prints the same (flash adds ≈ log(1+f) there).
        if flash > 0 { balance -= SIMD3(repeating: log10(1 + flash)) }

        // 1. Camera light -> spectral reconstruction -> exposure of each film layer.
        var R = img.r, G = img.g, B = img.b
        let gain = pow(2, filmEV)
        let derender = context.isDisplayReferred
        map3(&R, &G, &B) { r, g, b in
            var rr = r, gg = g, bb = b
            if derender {
                rr = midGrey * pow(max(rr, 0) / midGrey, 0.8)
                gg = midGrey * pow(max(gg, 0) / midGrey, 0.8)
                bb = midGrey * pow(max(bb, 0) / midGrey, 0.8)
            }
            let e = table.exposure(rr * gain, gg * gain, bb * gain)
            r = max(e.x, 1e-7); g = max(e.y, 1e-7); b = max(e.z, 1e-7)
        }

        // 2. Light scatter inside the emulsion. Light reaches the bottom (red) layer through the others,
        //    so the red record is softest and the top (blue) record sharpest.
        let soft = stock.softnessUm / pixelUm
        let layerScatter: SIMD3<Float> = stock.kind == .blackWhite ? [1, 1, 1] : [1.25, 1.0, 0.8]
        if !context.uniform && soft * layerScatter.max() > 0.3 {
            R = scatter(R, w, h, sigma: soft * layerScatter.x)
            G = scatter(G, w, h, sigma: soft * layerScatter.y)
            B = scatter(B, w, h, sigma: soft * layerScatter.z)
        }

        // 3. Halation: light reflected from the film base re-exposes the bottom (red) layers.
        let hal = stock.halationRGB * settings.halation
        if !context.uniform && hal.max() > 1e-4 {
            let clip = (context.clipLevel ?? (R.max() ?? 1)) * gain
            let rad = max(stock.halationRadiusUm / pixelUm, 0.5)
            func halo(_ p: [Float]) -> [Float] {
                // Blown highlights were brighter than the sensor recorded: boost them as light sources.
                let s = p.map { v in v * (1 + 4 * ColorFingerprint.smooth(0.85 * clip, clip, v)) }
                let near = Blur.gaussian(s, w, h, sigma: rad), far = Blur.gaussian(s, w, h, sigma: rad * 3)
                var out = near
                for i in 0..<out.count { out[i] = 0.65 * near[i] + 0.35 * far[i] }
                return out
            }
            // Energy-conserving: halation redistributes light, it does not add a global cast.
            if hal.x > 0 { let hr = halo(R); let k = 1 / (1 + hal.x); for i in 0..<R.count { R[i] = (R[i] + hal.x * hr[i]) * k } }
            if hal.y > 0 { let hg = halo(G); let k = 1 / (1 + hal.y); for i in 0..<G.count { G[i] = (G[i] + hal.y * hg[i]) * k } }
        }

        // 4. Log exposure.
        let logMid = log10(midGrey)
        let isBW = stock.kind == .blackWhite
        map3(&R, &G, &B) { r, g, b in
            r = log10(r) - logMid; g = log10(g) - logMid; b = log10(b) - logMid
        }

        // 5. DIR couplers: developing layers release inhibitors that diffuse and hold back development
        //    in the same layer (edge effects) and neighbouring layers (interimage colour saturation).
        applyDIR(&R, &G, &B, w: w, h: h, stock: stock, tone: tone, pixelUm: pixelUm, mono: isBW, uniform: context.uniform)

        // 6. Development: characteristic curves -> dye / silver density per layer.
        map3(&R, &G, &B) { r, g, b in
            r = model.density(r, 0, tone); g = model.density(g, 1, tone); b = model.density(b, 2, tone)
        }

        // 6b. Developer exhaustion: agitation-dependent adjacency, compensation and bromide drag.
        //     (Continuous agitation is what the datasheet curves and the DIR / adjacency model already describe.)
        if settings.agitation != .continuous {
            applyExhaustion(&R, &G, &B, w: w, h: h, agitation: settings.agitation,
                            midDensity: model.density(0, 1, tone), pixelUm: pixelUm, mono: isBW,
                            reversal: stock.kind == .slide, dmax: model.density(-4, 1, tone), uniform: context.uniform)
        }

        // 7. Grain: stochastic crystal counts per layer, coarse fast + fine slow sublayers.
        let grainBoost = context.uniform ? 0 : settings.grain * (1 + 0.25 * max(settings.push, 0))
        if let gl = model.grainLayers, !isBW {
            // Measured stocks: grain from the datasheet's fast / medium / slow sub-emulsions.
            addGrainLayered(&R, w: w, h: h, stock: stock, layers: gl, channel: 0, amount: grainBoost, context: context, pixelUm: pixelUm)
            addGrainLayered(&G, w: w, h: h, stock: stock, layers: gl, channel: 1, amount: grainBoost, context: context, pixelUm: pixelUm)
            addGrainLayered(&B, w: w, h: h, stock: stock, layers: gl, channel: 2, amount: grainBoost, context: context, pixelUm: pixelUm)
        } else {
            addGrain(&R, w: w, h: h, stock: stock, dmax: model.layerDmax, amount: grainBoost, context: context, pixelUm: pixelUm, channel: 0)
            if !isBW {
                addGrain(&G, w: w, h: h, stock: stock, dmax: model.layerDmax, amount: grainBoost, context: context, pixelUm: pixelUm, channel: 2)
                addGrain(&B, w: w, h: h, stock: stock, dmax: model.layerDmax, amount: grainBoost, context: context, pixelUm: pixelUm, channel: 4)
            }
        }

        // 8. Printing (negatives) / viewing (slides): spectral dyes -> paper -> D65 viewing.
        map3(&R, &G, &B) { r, g, b in
            var c = scanner?.render(SIMD3(r, g, b), balance: scanBal, fade: fade)
                ?? model.render(SIMD3(r, isBW ? r : g, isBW ? r : b), balance: balance, neutral: neutral, flash: flash, bwKp: bwKp, fade: fade)
            if !isBW { c = model.profile(c) }
            r = c.x; g = c.y; b = c.z
        }
        var out = RGBImage(width: w, height: h, r: R, g: G, b: B)

        // 8b. Lab scanner optics: its lens / CCD blur (≈ 4000 dpi class) and the fixed unsharp mask
        //     minilab scanners apply, which is part of the familiar crisp, grain-forward scan look.
        if scanner != nil && !context.uniform { scannerOptics(&out, pixelUm: pixelUm) }

        // 8c. Paper surface: lustre and matte papers reflect more light off their surface than glossy (whose
        //     0.4 % is already in the print model), lifting the blacks toward the paper white.
        if scanner == nil && stock.kind != .slide && settings.paperSurface != .glossy {
            let extra = (settings.paperSurface.flare - PaperSurface.glossy.flare) / (1 - PaperSurface.glossy.flare)
            for i in 0..<out.r.count {
                out.r[i] = out.r[i] * (1 - extra) + extra; out.g[i] = out.g[i] * (1 - extra) + extra; out.b[i] = out.b[i] * (1 - extra) + extra
            }
        }

        // 9. Optional residual look adjustment, gamut mapping, encode.
        if stock.hasResidual && !isBW {
            // Only the tonal crossovers: saturation / hue character is already built into the film model.
            var tints = stock
            tints.saturation = 1; tints.hueShift = Array(repeating: 0, count: 7)
            tints.hueSat = Array(repeating: 1, count: 7); tints.hueLum = Array(repeating: 0, count: 7)
            ColorFingerprint.apply(&out, stock: tints)
        }
        map3(&out.r, &out.g, &out.b) { r, g, b in
            // Out-of-gamut dye colours: desaturate toward luminance rather than clip the hue.
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            // Black point: printers and scanners set maximum density neutral, so dye imbalance at
            // D-max does not tint the deepest shadows.
            // (shifted up by the print's flare floor, ≈ 0.4 %)
            let bp = ColorFingerprint.smooth(0.005, 0.018, y)
            r = y + (r - y) * bp; g = y + (g - y) * bp; b = y + (b - y) * bp
            let mn = min(r, min(g, b))
            if mn < 0, y > 0 {
                let t = y / (y - mn)
                r = y + (r - y) * t; g = y + (g - y) * t; b = y + (b - y) * t
            }
            r = srgbEncode(r); g = srgbEncode(g); b = srgbEncode(b)
        }
        return out
    }

    // MARK: - Scanner optics

    static let scannerBlurUm: Float = 3.5, scannerSharpenUm: Float = 9, scannerSharpenAmount: Float = 0.65

    /// Scanner MTF (Gaussian) then unsharp masking on log luminance (hue-preserving, no colour fringes).
    static func scannerOptics(_ img: inout RGBImage, pixelUm: Float) {
        let w = img.width, h = img.height, n = w * h
        let blur = scannerBlurUm / pixelUm
        if blur > 0.3 {
            img.r = Blur.gaussian(img.r, w, h, sigma: blur); img.g = Blur.gaussian(img.g, w, h, sigma: blur); img.b = Blur.gaussian(img.b, w, h, sigma: blur)
        }
        let radius = scannerSharpenUm / pixelUm
        guard radius > 0.4 else { return }
        var L = [Float](repeating: 0, count: n)
        for i in 0..<n { L[i] = log(max(0.2126 * img.r[i] + 0.7152 * img.g[i] + 0.0722 * img.b[i], 1e-5)) }
        let Lb = Blur.gaussian(L, w, h, sigma: radius)
        for i in 0..<n {
            let k = exp(scannerSharpenAmount * min(max(L[i] - Lb[i], -0.5), 0.5))
            img.r[i] *= k; img.g[i] *= k; img.b[i] *= k
        }
    }

    // MARK: - Optical scatter

    /// Light scatter in a turbid emulsion has long tails: the line spread is close to exponential, giving
    /// the Frieser MTF 1/(1+(f/fc)²) rather than a Gaussian's fast roll-off — fine detail survives at low
    /// contrast while a soft veil spreads around bright edges. The PSF is a 4-Gaussian fit of that MTF
    /// (max error 0.003); fc is set so the 50 % point matches a Gaussian of `sigma` (the stock's
    /// softness), keeping overall sharpness calibrated.
    static let scatterLobes: [(scale: Float, weight: Float)] = {
        let raw: [(Float, Float)] = [(0.04, 0.07199), (0.08, 0.12736), (0.16, 0.44680), (0.32, 0.35253)]
        let t = raw.map { $0.1 }.reduce(0, +)
        return raw.map { (scale: $0.0 / 0.18739, weight: $0.1 / t) }   // in units of the Gaussian sigma
    }()

    static func scatter(_ p: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
        var out = [Float](repeating: 0, count: p.count)
        for lobe in scatterLobes {
            let s = sigma * lobe.scale
            let b = s < 0.25 ? p : Blur.gaussian(p, w, h, sigma: s)
            for i in 0..<out.count { out[i] += lobe.weight * b[i] }
        }
        return out
    }

    // MARK: - DIR couplers

    static func applyDIR(_ r: inout [Float], _ g: inout [Float], _ b: inout [Float], w: Int, h: Int,
                         stock: FilmStock, tone: FilmModel.Tone, pixelUm: Float, mono: Bool, uniform: Bool = false) {
        let same = stock.dirSame, inter = mono ? 0 : stock.dirInter
        if same + inter < 1e-4 { return }
        let lo: Float = stock.kind == .slide ? -2.2 : tone.toe
        let hi: Float = stock.kind == .slide ? 1.3 : tone.shoulder
        func inhibitor(_ p: [Float]) -> [Float] {
            let c = p.map { softClip($0, lo, hi) }
            return uniform ? c : Blur.gaussian(c, w, h, sigma: stock.dirSpreadUm / pixelUm)
        }
        let ir = inhibitor(r)
        if mono {
            let k = 1 / (1 - same)
            for i in 0..<r.count { r[i] = (r[i] - same * ir[i]) * k }
            return
        }
        let ig = inhibitor(g), ib = inhibitor(b)
        let k = 1 / (1 - same - 2 * inter)
        for i in 0..<r.count {
            let a = ir[i], c = ig[i], d = ib[i]
            r[i] = (r[i] - same * a - inter * (c + d)) * k
            g[i] = (g[i] - same * c - inter * (a + d)) * k
            b[i] = (b[i] - same * d - inter * (a + c)) * k
        }
    }

    // MARK: - Grain

    /// Grain from crystal statistics. Density is the fraction p of developed crystals times Dmax, so its
    /// variance is Dmax²·p(1−p)/N for N crystals under a pixel. Two sublayers: a fast emulsion of large
    /// crystals that fills first (p_f = 1−(1−p)²) and a slow fine one (p_s = p²). N is calibrated so the
    /// RMS granularity at D = 1 through a 48 µm aperture matches the datasheet; per-pixel N then follows
    /// the pixel area (Selwyn's law) until the pixel is smaller than the dye clouds.
    static func addGrain(_ d: inout [Float], w: Int, h: Int, stock: FilmStock, dmax: Float, amount: Float,
                         context: DevelopContext, pixelUm: Float, channel: UInt32) {
        let cal = stock.kind == .blackWhite ? grainCalibration * 0.55 : grainCalibration
        let s48 = stock.grainRMS / 1000 * cal * amount
        if s48 < 1e-5 { return }
        let p1 = min(1 / dmax, 0.95)
        let pf1 = 1 - (1 - p1) * (1 - p1), ps1 = p1 * p1
        let n48 = dmax * dmax * 0.25 * (pf1 * (1 - pf1) + ps1 * (1 - ps1) / 4) / (s48 * s48)
        let a48 = Float.pi * 24 * 24
        let cloud = stock.grainSizeUm
        let pixA = pixelUm * pixelUm
        // grainSizeUm is the dye-cloud / clump diameter; the fine sublayer's clouds are 0.6× that.
        let cloudArea = Float.pi * cloud * cloud / 4
        let nf = n48 * max(pixA, cloudArea) / a48
        let ns = 4 * n48 * max(pixA, cloudArea * 0.36) / a48

        let fast = Noise.grain(w, h, originX: context.originX, originY: context.originY, seed: context.seed,
                               channel: channel, sizePx: 0.5 * cloud / pixelUm)
        let slow = Noise.grain(w, h, originX: context.originX, originY: context.originY, seed: context.seed,
                               channel: channel + 1, sizePx: 0.3 * cloud / pixelUm)
        let kf = dmax * 0.5 / nf.squareRoot(), ks = dmax * 0.5 / ns.squareRoot()
        d.withUnsafeMutableBufferPointer { dp in
            let D = dp.baseAddress!, n = dp.count
            Parallel.rows((n + 4095) / 4096) { blocks in
                for blk in blocks {
                    let a = blk * 4096, e = min(n, a + 4096)
                    for i in a..<e {
                        let p = min(max(D[i] / dmax, 0), 0.999)
                        let pf = 1 - (1 - p) * (1 - p), ps = p * p
                        // Crystal counts are binomial, not Gaussian: few developed grains in thin areas give a
                        // positively skewed, speckly texture. Cornish–Fisher skew correction of the unit field.
                        let vf = max(nf * pf * (1 - pf), 1e-6), vs = max(ns * ps * (1 - ps), 1e-6)
                        let gf = min(max((1 - 2 * pf) / vf.squareRoot(), -1.5), 1.5)
                        let gs = min(max((1 - 2 * ps) / vs.squareRoot(), -1.5), 1.5)
                        let zf = fast[i], zs = slow[i]
                        let sf = zf + gf / 6 * (zf * zf - 1), ss = zs + gs / 6 * (zs * zs - 1)
                        D[i] += kf * (pf * (1 - pf)).squareRoot() * sf + ks * (ps * (1 - ps)).squareRoot() * ss
                    }
                }
            }
        }
    }

    /// Parallel per-pixel map over three planes.
    static func map3(_ r: inout [Float], _ g: inout [Float], _ b: inout [Float], _ f: (inout Float, inout Float, inout Float) -> Void) {
        let n = r.count
        r.withUnsafeMutableBufferPointer { rp in
        g.withUnsafeMutableBufferPointer { gp in
        b.withUnsafeMutableBufferPointer { bp in
            let R = rp.baseAddress!, G = gp.baseAddress!, B = bp.baseAddress!
            Parallel.rows((n + 4095) / 4096) { blocks in
                for blk in blocks {
                    let a = blk * 4096, e = min(n, a + 4096)
                    for i in a..<e { f(&R[i], &G[i], &B[i]) }
                }
            }
        }}}
    }
}

/// Optional stock-specific residual rendering in Oklab (display-linear sRGB in/out).
enum ColorFingerprint {
    static func apply(_ img: inout RGBImage, stock: FilmStock) {
        let centers = HueSector.allCases.map { $0.center }
        let widths = HueSector.allCases.map { $0.width }
        let shifts = stock.hueShift, sats = stock.hueSat, lums = stock.hueLum
        let gsat = stock.saturation
        let st = stock.shadowTint, ht = stock.highlightTint
        Developer.map3(&img.r, &img.g, &img.b) { r, g, b in
            let l = cbrt(max(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 0))
            let m = cbrt(max(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 0))
            let s = cbrt(max(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 0))
            var L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            var A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            var Bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            let C = (A * A + Bb * Bb).squareRoot()
            if C > 1e-5 {
                var hue = atan2(Bb, A) * 57.29578
                if hue < 0 { hue += 360 }
                var dh: Float = 0, ds: Float = 0, dl: Float = 0
                for i in 0..<7 {
                    var d = abs(hue - centers[i]); if d > 180 { d = 360 - d }
                    let t = d / widths[i]
                    let wgt = exp(-t * t)
                    dh += wgt * shifts[i]; ds += wgt * (sats[i] - 1); dl += wgt * lums[i]
                }
                let newC = C * gsat * max(1 + ds, 0)
                let nh = (hue + dh) * 0.017453293
                A = newC * cos(nh); Bb = newC * sin(nh)
                L *= 1 + dl * min(C / 0.12, 1)
            }
            let ws = 1 - smooth(0.15, 0.6, L), wh = smooth(0.55, 0.95, L)
            A += ws * st.x + wh * ht.x
            Bb += ws * st.y + wh * ht.y
            let l2 = L + 0.3963377774 * A + 0.2158037573 * Bb
            let m2 = L - 0.1055613458 * A - 0.0638541728 * Bb
            let s2 = L - 0.0894841775 * A - 1.2914855480 * Bb
            let l3 = l2 * l2 * l2, m3 = m2 * m2 * m2, s3 = s2 * s2 * s2
            r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
            g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
            b = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        }
    }

    @inline(__always) static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
