import Foundation
import simd

/// Trilinear 3D lookup table over [0, maxIn]³.
struct LUT3 {
    let n: Int
    let maxIn: Float
    var data: [SIMD3<Float>]

    init(n: Int, maxIn: Float, _ f: (SIMD3<Float>) -> SIMD3<Float>) {
        self.n = n; self.maxIn = maxIn
        var d = [SIMD3<Float>](repeating: .zero, count: n * n * n)
        let step = maxIn / Float(n - 1)
        d.withUnsafeMutableBufferPointer { p in
            DispatchQueue.concurrentPerform(iterations: n) { z in
                for y in 0..<n {
                    for x in 0..<n {
                        p[(z * n + y) * n + x] = f(SIMD3(Float(x), Float(y), Float(z)) * step)
                    }
                }
            }
        }
        data = d
    }

    @inline(__always) func sample(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let s = Float(n - 1) / maxIn
        let fx = min(max(v.x * s, 0), Float(n - 1) - 0.0001)
        let fy = min(max(v.y * s, 0), Float(n - 1) - 0.0001)
        let fz = min(max(v.z * s, 0), Float(n - 1) - 0.0001)
        let ix = Int(fx), iy = Int(fy), iz = Int(fz)
        let tx = fx - Float(ix), ty = fy - Float(iy), tz = fz - Float(iz)
        let i000 = (iz * n + iy) * n + ix
        let a = data[i000], b = data[i000 + 1], c = data[i000 + n], d = data[i000 + n + 1]
        let o = n * n
        let e = data[i000 + o], f = data[i000 + o + 1], g = data[i000 + o + n], h = data[i000 + o + n + 1]
        let ab = a + (b - a) * tx, cd = c + (d - c) * tx, ef = e + (f - e) * tx, gh = g + (h - g) * tx
        let lo = ab + (cd - ab) * ty, hi = ef + (gh - ef) * ty
        return lo + (hi - lo) * tz
    }
}

/// Per-channel grey-scale calibration: offsets (keyed by each channel's own value) that keep a neutral
/// grey ramp neutral from deep shadow to highlight, as film and paper makers balance their emulsions.
struct Neutralizer {
    var keys: [[Float]] = [[], [], []]   // ascending
    var vals: [[Float]] = [[], [], []]
    /// Printer balance the table was built at; keys are shifted by (balance − this) so the correction
    /// follows the paper exposure actually used when a frame is printed lighter or darker.
    var refBalance: SIMD3<Float> = .zero
    static let identity = Neutralizer()

    @inline(__always) func offset(_ c: Int, _ v: Float) -> Float {
        let k = keys[c]
        let n = k.count
        if n == 0 { return 0 }
        if v <= k[0] { return vals[c][0] }
        if v >= k[n - 1] { return vals[c][n - 1] }
        var lo = 0, hi = n - 1
        while hi - lo > 1 { let m = (lo + hi) >> 1; if k[m] <= v { lo = m } else { hi = m } }
        let t = (v - k[lo]) / max(k[hi] - k[lo], 1e-9)
        return vals[c][lo] + (vals[c][hi] - vals[c][lo]) * t
    }
}

/// Everything precomputed for one film stock: spectral tables, LUTs and neutral balance.
final class FilmModel {
    let stock: FilmStock
    let print: PrintProfile
    let sensitivities: [[Float]]
    let reference: [Float]                 // illuminant the film is balanced for
    private(set) var refTable: ExposureTable
    private(set) var rawTable: ExposureTable
    /// Scanner profile fitted on a ColorChecker: per hue-sector Oklab hue shift (deg) and log-chroma gain.
    private(set) var profileHue = [Float](repeating: 0, count: 7)
    private(set) var profileSat = [Float](repeating: 0, count: 7)
    var hasProfile: Bool { stock.kind != .blackWhite }
    /// Hue calibration in layer-exposure space (rows sum to 1, so neutrals are untouched).
    private(set) var hueCalibration = Spectral.M3(r0: [1, 0, 0], r1: [0, 1, 0], r2: [0, 0, 1])
    /// Measured datasheet data (film), when available.
    let measured: MeasuredProfile?
    private(set) var filmCurves: [[Float]] = []
    private(set) var pushCurves: [[[Float]]] = []
    private(set) var paperCurves: [[Float]] = []
    /// Slides: measured log exposure that renders mid grey at density ≈ 0.8 (normal metering).
    private(set) var slideMid: Float = 0
    /// Max density over base per layer (sets grain statistics).
    private(set) var layerDmax: Float = 2.4
    /// Measured sub-emulsion grain statistics (measured stocks).
    private(set) var grainLayers: GrainLayers?
    var negToPrint: LUT3?                  // negative densities -> log10 print exposures
    var display: LUT3?                     // print / slide densities -> display-linear sRGB
    let paperKp: Float

    private static var cache: [String: FilmModel] = [:]
    private static let lock = NSLock()
    private var sceneCache: [Int: ExposureTable] = [:]
    private var neutralCache: [Int: Neutralizer] = [:]

    func cachedNeutralizer(push: Float) -> Neutralizer {
        let key = Int((push * 10).rounded())
        sceneLock.lock()
        if let n = neutralCache[key] { sceneLock.unlock(); return n }
        sceneLock.unlock()
        let n = neutralizer(push: push)
        sceneLock.lock(); neutralCache[key] = n; sceneLock.unlock()
        return n
    }
    private let sceneLock = NSLock()

    static func model(for stock: FilmStock) -> FilmModel {
        lock.lock(); defer { lock.unlock() }
        if let m = cache[stock.id] { return m }
        let m = FilmModel(stock)
        cache[stock.id] = m
        return m
    }

    @inline(__always) static func tab(_ v: [Float], _ x: Float) -> Float {
        let f = (x - MeasuredData.logExposureStart) / MeasuredData.logExposureStep
        let n = v.count
        if f <= 0 { return v[0] }
        if f >= Float(n - 1) { return v[n - 1] }
        let i = Int(f), t = f - Float(i)
        return v[i] + (v[i + 1] - v[i]) * t
    }
    /// Inverse of a monotonic tabulated curve (first crossing of density `d`).
    static func tabInverse(_ v: [Float], _ d: Float) -> Float {
        let increasing = (v.last ?? 0) > (v.first ?? 0)
        for i in 0..<(v.count - 1) {
            let a = v[i], b = v[i + 1]
            if increasing ? (a <= d && b >= d) : (a >= d && b <= d) {
                let t = (d - a) / ((b - a) == 0 ? 1 : (b - a))
                return MeasuredData.logExposureStart + (Float(i) + t) * MeasuredData.logExposureStep
            }
        }
        return 0
    }

    private init(_ stock: FilmStock) {
        self.stock = stock
        print = PrintProfile.of(stock.medium)
        measured = stock.measured.flatMap { MeasuredData.profile($0) }
        var sens = measured?.sensitivity ?? stock.sensitivity.map { $0.sampled }
        if stock.kind == .blackWhite { sens = [sens[0], sens[0], sens[0]] }
        if let f = stock.fourthLayer {
            // DIR inhibition from the cyan-sensitive 4th layer acts like a negative red lobe.
            let s4 = [f].sampled
            let rPeak = sens[0].max() ?? 1
            sens[0] = (0..<Spectral.count).map { sens[0][$0] - f.weight * rPeak * s4[$0] }
        }
        sensitivities = sens
        reference = Spectral.illuminant(kelvin: stock.balanceKelvin)
        refTable = SpectralUpsampler.shared.exposureTable(sensitivities: sens, illuminant: reference, reference: reference)
        rawTable = refTable

        let range = print.range
        let f = Developer.midGreyDensity / range
        paperKp = stock.paperContrast / (range * f * (1 - f))

        pushCurves = stock.pushProfiles.compactMap { MeasuredData.profile($0)?.curves }
        if let m = measured {
            filmCurves = m.curves
            grainLayers = GrainLayers(m)
            layerDmax = (0..<3).map { m.curves[$0].max() ?? 2 }.reduce(0, +) / 3
            if stock.kind == .slide {
                let mean = (0..<m.curves[0].count).map { i in (m.curves[0][i] + m.curves[1][i] + m.curves[2][i]) / 3 }
                slideMid = Self.tabInverse(mean, 0.8)
            }
        } else {
            layerDmax = stock.layerDmax
        }
        if let pm = print.measured { paperCurves = pm.curves }

        switch stock.kind {
        case .colorNegative: buildNegative()
        case .slide: buildSlide()
        case .blackWhite: break
        }
        // Fitted stocks are calibrated toward documented character; measured stocks keep the data's own.
        if stock.kind != .blackWhite && measured == nil {
            rawTable = refTable
            hueCalibration = fitHueCalibration()
            refTable = refTable.applying(hueCalibration)
            fitScannerProfile()
        }
    }

    // MARK: Build

    private func buildNegative() {
        let dyes = measured?.dyes ?? stock.dyes.map { $0.sampled }
        let lamp = Spectral.enlarger(kelvin: print.enlargerKelvin)
        let ps = print.sensitivitySampled
        let norms = ps.map { s in (0..<Spectral.count).map { s[$0] * lamp[$0] }.reduce(0, +) }
        // Film base incl. the orange colour mask (measured), else a neutral 0.15.
        let base = measured?.base ?? [Float](repeating: 0.15, count: Spectral.count)
        negToPrint = LUT3(n: 33, maxIn: 3.2) { d in
            var out = SIMD3<Float>.zero
            var t = [Float](repeating: 0, count: Spectral.count)
            for i in 0..<Spectral.count {
                let dens = base[i] + d.x * dyes[0][i] + d.y * dyes[1][i] + d.z * dyes[2][i]
                t[i] = pow(10, -dens) * lamp[i]
            }
            for j in 0..<3 {
                var acc: Float = 0
                for i in 0..<Spectral.count { acc += t[i] * ps[j][i] }
                out[j] = log10(max(acc / norms[j], 1e-9))
            }
            return out
        }
        // Cinema print is judged on a xenon-arc projector (≈ 5400 K daylight-like); paper under D50.
        let viewing = stock.medium == .cinePrint ? Spectral.illuminant(kelvin: 5400) : Spectral.d50
        display = Self.displayLUT(dyes: print.dyesSampled, base: print.baseSpectrum, maxIn: print.measuredRange + 0.3,
                                  balance: print.measured == nil, viewing: viewing,
                                  flare: stock.medium == .cinePrint ? Self.projectionFlare : Self.paperFlare)
    }
    private var range: Float { print.measured != nil ? print.measuredRange : print.range }
    var printRange: Float { range }
    /// Non-image light: glossy RA-4 paper's first-surface reflection under 45°/0° viewing (≈ 0.4 %),
    /// a light box / scanner's veiling glare for transparencies, and screen flare for projection.
    static let paperFlare: Float = 0.004, transparencyFlare: Float = 0.0015, projectionFlare: Float = 0.002

    private func buildSlide() {
        if let m = measured {
            display = Self.displayLUT(dyes: m.dyes, base: m.base, maxIn: (m.curves.flatMap { $0 }.max() ?? 3) + 0.4, balance: false,
                                      flare: Self.transparencyFlare)
        } else {
            display = Self.displayLUT(dyes: stock.dyes.map { $0.sampled }, base: [Float](repeating: 0.12, count: Spectral.count),
                                      maxIn: stock.slideRange + 0.6, balance: true, flare: Self.transparencyFlare)
        }
    }

    /// Dye densities -> spectral transmittance/reflectance -> XYZ under D65 -> white-adapted linear sRGB.
    /// Dye strengths are first grey-balanced (equal densities of the three dyes look neutral), which is
    /// how manufacturers specify image dyes ("equivalent neutral density").
    ///
    /// `viewing` is the light the print / slide is judged under (D50 per ISO 3664 and the datasheets;
    /// the eye then adapts to its white), and `flare` the fraction of light that never passes through
    /// the dyes — first-surface reflection of the paper, or light-box / scanner veiling glare — which is
    /// what limits real blacks to a visual density of about 2.3–2.5.
    static func displayLUT(dyes rawDyes: [[Float]], base: [Float], maxIn: Float, balance: Bool,
                           viewing: [Float] = Spectral.d50, flare: Float = 0) -> LUT3 {
        var dyes = rawDyes
        func xyz(_ d: SIMD3<Float>) -> SIMD3<Float> {
            var spd = [Float](repeating: 0, count: Spectral.count)
            for i in 0..<Spectral.count {
                let dens = base[i] + d.x * dyes[0][i] + d.y * dyes[1][i] + d.z * dyes[2][i]
                // Flare is judged against the adapted paper white, so it carries the white's colour.
                spd[i] = ((1 - flare) * pow(10, -dens) + flare * pow(10, -base[i])) * viewing[i]
            }
            return Spectral.xyz(spd)
        }
        let white = xyz(.zero)
        let scale = 1 / white.y
        let adapt = Spectral.adaptation(from: white * scale)   // paper / film-base white -> display white
        func rgb(_ d: SIMD3<Float>) -> SIMD3<Float> { Spectral.xyzToSRGB.apply(adapt(xyz(d) * scale)) }
        // Grey-balance near maximum density (where blacks live): scale each dye until equal amounts
        // render neutral. Mid-tones are kept neutral separately by the per-stock grey-scale calibration.
        let dBal = min(maxIn * 0.75, 2.2)
        for _ in 0..<(balance ? 60 : 0) {
            let c = rgb(SIMD3(repeating: dBal))
            let l = SIMD3(log10(max(c.x, 1e-9)), log10(max(c.y, 1e-9)), log10(max(c.z, 1e-9)))
            let err = l - SIMD3(repeating: l.sum() / 3)
            if abs(err).max() < 1e-4 { break }
            for k in 0..<3 {
                let f = min(max(pow(10, err[k] / dBal * 0.8), 0.8), 1.25)   // too bright -> strengthen that dye
                dyes[k] = dyes[k].map { $0 * f }
            }
        }
        return LUT3(n: 33, maxIn: maxIn) { d in
            Spectral.xyzToSRGB.apply(adapt(xyz(d) * scale))
        }
    }

    // MARK: Tone (per develop: push/pull changes development contrast)

    struct Tone {
        var gamma: SIMD3<Float>
        var toe: Float, shoulder: Float
        var slideK: SIMD3<Float>, slideX0: SIMD3<Float>, slideRange: Float
        /// Measured curves for this development (blended push profiles), and residual axis scaling.
        var curves: [[Float]] = []
        var axisScale: Float = 1
        /// Expired-film changes (speed loss, fog, flatter curve).
        var aging = Aging.none
    }

    func tone(push: Float, aging: Aging) -> Tone {
        var t = tone(push: push)
        t.aging = aging
        return t
    }

    func tone(push: Float) -> Tone {
        // Pushing = longer development: ~+12 % contrast per stop (typical datasheet push curves).
        let g = stock.gammaRGB * stock.contrast * (1 + 0.12 * push)
        let range = stock.slideRange
        let lm = 1 - Developer.midGreyDensity / range
        let k = g / (range * lm * (1 - lm))
        var t = Tone(gamma: g, toe: stock.toe - 0.15 * min(push, 0), shoulder: stock.shoulder,
                     slideK: k, slideX0: SIMD3(repeating: -Developer.logit(lm)) / k, slideRange: range)
        if measured != nil {
            t.curves = filmCurves
            t.axisScale = 1 + 0.12 * push
            let levels = [filmCurves] + pushCurves
            if levels.count > 1 && push > 0 {
                // Measured push development: blend between the datasheet's push curves.
                let p = min(push, Float(levels.count - 1))
                let i = min(Int(p), levels.count - 2), f = p - Float(i)
                t.curves = (0..<3).map { c in zip(levels[i][c], levels[i + 1][c]).map { $0 + ($1 - $0) * f } }
                t.axisScale = 1 + 0.12 * max(push - Float(levels.count - 1), 0)
            }
        }
        return t
    }

    @inline(__always) func density(_ x: Float, _ c: Int, _ t: Tone) -> Float {
        if t.aging.isNone { return freshDensity(x, c, t) }
        let a = t.aging
        let d = freshDensity(x - a.speedLoss[c], c, t) * a.gain
        // Negatives: fog adds density everywhere. Reversal: fog in the first developer removes dye,
        // lowering D-max (muddy, coloured blacks).
        return stock.kind == .slide ? d * (1 - min(a.fog[c], 0.6)) : d + a.fog[c]
    }

    @inline(__always) func freshDensity(_ x: Float, _ c: Int, _ t: Tone) -> Float {
        if !t.curves.isEmpty {
            // Measured characteristic curve (push profiles where measured, else axis scaling about mid grey).
            return Self.tab(t.curves[c], (stock.kind == .slide ? slideMid : 0) + x * t.axisScale)
        }
        if stock.kind == .slide {
            return t.slideRange * (1 - Developer.logistic(t.slideK[c] * (x - t.slideX0[c])))
        }
        return Developer.negCurve(x, gamma: t.gamma[c], toe: t.toe, shoulder: t.shoulder)
    }

    /// Printed (negative) or viewed (slide) display-linear colour for layer densities `d`.
    /// Paper log exposure that prints mid-scale density, per paper layer (for pre-flashing).
    var paperMidExposure: SIMD3<Float> {
        if !paperCurves.isEmpty {
            return SIMD3(Self.tabInverse(paperCurves[0], 0.75), Self.tabInverse(paperCurves[1], 0.75), Self.tabInverse(paperCurves[2], 0.75))
        }
        return SIMD3(repeating: Developer.logit(Developer.midGreyDensity / range) / paperKp)
    }

    /// `flash`: pre-flash exposure as a fraction of the paper's mid-scale exposure — a uniform, sub-threshold
    /// exposure given to the paper before printing, which lifts it out of its toe so the faintest
    /// highlight detail of a dense negative prints instead of staying paper-white.
    @inline(__always) func render(_ d: SIMD3<Float>, balance: SIMD3<Float>, neutral n: Neutralizer = .identity,
                                  flash: Float = 0, bwKp: Float = 0, fade: Fade? = nil) -> SIMD3<Float> {
        switch stock.kind {
        case .colorNegative:
            var lp = negToPrint!.sample(d)
            let k = lp + (balance - n.refBalance)
            lp = SIMD3(lp.x + n.offset(0, k.x), lp.y + n.offset(1, k.y), lp.z + n.offset(2, k.z)) + balance
            if flash > 0 {
                let m = paperMidExposure
                lp = SIMD3(log10(pow(10, lp.x) + flash * pow(10, m.x)), log10(pow(10, lp.y) + flash * pow(10, m.y)),
                           log10(pow(10, lp.z) + flash * pow(10, m.z)))
            }
            var dp: SIMD3<Float>
            if !paperCurves.isEmpty {
                dp = SIMD3(Self.tab(paperCurves[0], lp.x), Self.tab(paperCurves[1], lp.y), Self.tab(paperCurves[2], lp.z))
            } else {
                dp = SIMD3(range * Developer.logistic(paperKp * lp.x),
                           range * Developer.logistic(paperKp * lp.y),
                           range * Developer.logistic(paperKp * lp.z))
            }
            if let f = fade { dp = f.apply(dp) }
            return display!.sample(dp)
        case .slide:
            // Balance scales density, so clear film (D = 0) always stays clear.
            let dd = SIMD3(d.x + n.offset(0, d.x), d.y + n.offset(1, d.y), d.z + n.offset(2, d.z))
            var ds = simd_max(dd * SIMD3(exp(balance.x), exp(balance.y), exp(balance.z)), .zero)
            if let f = fade { ds = f.apply(ds) }
            return display!.sample(ds)
        case .blackWhite:
            let kp = bwKp > 0 ? bwKp : paperKp
            var lp = balance.x - d.x
            if flash > 0 { lp = log10(pow(10, lp) + flash * pow(10, Developer.logit(Developer.midGreyDensity / range) / kp)) }
            var dp = range * Developer.logistic(kp * lp)
            if let f = fade { dp = f.silver(dp) }
            let v = SIMD3(repeating: (1 - Self.paperFlare) * pow(10, -dp) + Self.paperFlare)
            return fade.map { v * $0.silverTint } ?? v
        }
    }

    /// Builds the grey-scale calibration for this development (uniform layer gammas, so any intended
    /// per-layer crossover in `gammaRGB` survives it).
    func neutralizer(push: Float) -> Neutralizer {
        // Cross-processed film: the crossovers *are* the look; a lab can only set one balance per frame.
        if stock.kind == .blackWhite || stock.isCrossProcessed { return .identity }
        var t = tone(push: push)
        t.gamma = SIMD3(repeating: stock.contrast * (1 + 0.12 * push))
        let range = t.slideRange, lm = 1 - Developer.midGreyDensity / range
        t.slideK = t.gamma / (range * lm * (1 - lm)); t.slideX0 = SIMD3(repeating: -Developer.logit(lm)) / t.slideK
        let mid = solveNeutral(greyDensities: greyDensities(table: refTable, tone: t, ev: 0), withCast: false)
        var nz = Neutralizer()
        nz.refBalance = stock.kind == .colorNegative ? mid : .zero
        var entries: [[(Float, Float)]] = [[], [], []]
        var prev = SIMD3<Float>.zero
        // Walk out from mid grey in both directions (−7…+9 stops), warm-starting each solve.
        let stops = Array(stride(from: Float(0), through: 9, by: 0.5)) + Array(stride(from: Float(-0.5), through: -7, by: -0.5))
        for ev in stops {
            if ev == -0.5 { prev = mid }
            let g = greyDensities(table: refTable, tone: t, ev: ev)
            let y = luminance(render(g, balance: mid))
            var o = solveNeutral(greyDensities: g, withCast: false, targetY: y, start: prev == .zero ? mid : prev)
            // Reject a solve that failed to converge (deep toe / shoulder): keep the last good offset.
            let c = render(g, balance: o)
            if !(o.x.isFinite && o.y.isFinite && o.z.isFinite) || abs(log10(max(c.max(), 1e-6) / max(c.min(), 1e-6))) > 0.02 {
                o = prev == .zero ? mid : prev
            }
            prev = o
            let key: SIMD3<Float> = stock.kind == .colorNegative ? negToPrint!.sample(g) : g
            for c in 0..<3 {
                // Negatives: additive printer-light offset. Slides: additive density, applied before the
                // multiplicative mid balance, equivalent to scaling by exp(o − mid).
                let v = stock.kind == .colorNegative ? o[c] - mid[c] : g[c] * (exp(o[c] - mid[c]) - 1)
                entries[c].append((key[c], v))
            }
        }
        for c in 0..<3 {
            let e = entries[c].sorted { $0.0 < $1.0 }
            nz.keys[c] = e.map { $0.0 }; nz.vals[c] = e.map { $0.1 }
        }
        return nz
    }

    // MARK: Hue calibration

    /// ColorChecker chromatic patches (sRGB, 8-bit).
    static let checker: [SIMD3<Float>] = [
        [115, 82, 68], [194, 150, 130], [98, 122, 157], [87, 108, 67], [133, 128, 177], [103, 189, 170],
        [214, 126, 44], [80, 91, 166], [193, 90, 99], [94, 60, 108], [157, 188, 64], [224, 163, 46],
        [56, 61, 150], [70, 148, 73], [175, 54, 60], [231, 199, 31], [187, 86, 149], [8, 133, 161]]

    static func oklab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = cbrt(max(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z, 0))
        let m = cbrt(max(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z, 0))
        let s = cbrt(max(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z, 0))
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func srgbDecode(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

    /// Render a uniform patch (linear Rec.2020 in) through the whole chain without spatial effects.
    func renderUniform(_ rgb: SIMD3<Float>, table: ExposureTable, matrix: Spectral.M3, tone t: Tone,
                       balance: SIMD3<Float>, neutral nz: Neutralizer) -> SIMD3<Float> {
        let e = matrix.apply(table.exposure(rgb.x, rgb.y, rgb.z))
        var x = SIMD3<Float>.zero
        for k in 0..<3 { x[k] = log10(max(e[k], 1e-7)) - log10(Developer.midGrey) }
        let xp = uniformDIR(x, t)
        let d = SIMD3(density(xp.x, 0, t), density(xp.y, 1, t), density(xp.z, 2, t))
        return render(d, balance: balance, neutral: nz)
    }

    /// Fits off-diagonal exposure crosstalk so ColorChecker hues come out right (chroma and lightness
    /// are left to the film), compensating the imprecision of lobe-fitted datasheet spectra.
    func fitHueCalibration() -> Spectral.M3 {
        let t = tone(push: 0)
        let nz = neutralizer(push: 0)
        let bal = solveNeutral(greyDensities: greyDensities(table: refTable, tone: t, ev: 0), withCast: false, neutral: nz)
        let patches = Self.checker.map { c -> (SIMD3<Float>, SIMD3<Float>) in
            let lin = SIMD3(Self.srgbDecode(c.x / 255), Self.srgbDecode(c.y / 255), Self.srgbDecode(c.z / 255))
            let xyz = Spectral.srgbToXYZ.apply(lin)
            return (Spectral.xyzToRec2020.apply(xyz), Spectral.lab(xyz))
        }
        func matrix(_ p: [Float]) -> Spectral.M3 {
            Spectral.M3(r0: [1 - p[0] - p[1], p[0], p[1]], r1: [p[2], 1 - p[2] - p[3], p[3]], r2: [p[4], p[5], 1 - p[4] - p[5]])
        }
        // Target: true patch colour with this stock's documented character (saturation, hue bias) applied,
        // compared as chroma-per-lightness in Oklab so lightness is left to the film's tone curve.
        let targets: [SIMD2<Float>] = patches.map { rgb, _ in
            let lin = Spectral.xyzToSRGB.apply(Spectral.rec2020ToXYZ.apply(rgb))
            let lab = Self.oklab(stock.applyingLook(lin))
            return SIMD2(lab.y, lab.z) / max(lab.x, 0.05)
        }
        func residuals(_ p: [Float]) -> [Float] {
            let m = matrix(p)
            var r: [Float] = []
            for (i, (rgb, _)) in patches.enumerated() {
                let out = renderUniform(rgb, table: refTable, matrix: m, tone: t, balance: bal, neutral: nz)
                let lab = Self.oklab(simd_max(out, SIMD3(repeating: 1e-5)))
                let sv = SIMD2(lab.y, lab.z) / max(lab.x, 0.05)
                let d = (sv - targets[i]) * 10
                r.append(d.x); r.append(d.y)
            }
            for v in p { r.append(v * 20) }    // strongly regularised: keep layer sensitivities narrow and physical
            return r
        }
        var p = [Float](repeating: 0, count: 6)
        var lambda: Float = 1e-2
        var r = residuals(p)
        var err = r.map { $0 * $0 }.reduce(0, +)
        for _ in 0..<40 {
            var J = [[Float]](repeating: [Float](repeating: 0, count: 6), count: r.count)
            for j in 0..<6 {
                var q = p; q[j] += 1e-3
                let rq = residuals(q)
                for i in 0..<r.count { J[i][j] = (rq[i] - r[i]) / 1e-3 }
            }
            var A = [[Float]](repeating: [Float](repeating: 0, count: 6), count: 6), g = [Float](repeating: 0, count: 6)
            for a in 0..<6 {
                for b in 0..<6 { A[a][b] = (0..<r.count).map { J[$0][a] * J[$0][b] }.reduce(0, +) }
                g[a] = (0..<r.count).map { J[$0][a] * r[$0] }.reduce(0, +)
            }
            var improved = false
            for _ in 0..<6 {
                var Ad = A
                for a in 0..<6 { Ad[a][a] *= 1 + lambda; Ad[a][a] += 1e-6 }
                guard let step = Self.solve(Ad, g) else { lambda *= 10; continue }
                let q = zip(p, step).map { min(max($0 - $1, -0.8), 0.8) }
                let rq = residuals(q), eq = rq.map { $0 * $0 }.reduce(0, +)
                if eq < err { p = q; r = rq; err = eq; lambda = max(lambda * 0.3, 1e-6); improved = true; break }
                lambda *= 10
            }
            if !improved { break }
        }
        return matrix(p)
    }

    /// Stage 2: like a lab profiling its scanner with an IT8/ColorChecker target, solve per-sector hue and
    /// chroma corrections (ridge least squares) for the error the physical model leaves.
    func fitScannerProfile() {
        let t = tone(push: 0), nz = neutralizer(push: 0)
        let bal = solveNeutral(greyDensities: greyDensities(table: refTable, tone: t, ev: 0), withCast: false, neutral: nz)
        let id = Spectral.M3(r0: [1, 0, 0], r1: [0, 1, 0], r2: [0, 0, 1])
        var W: [[Float]] = [], eh: [Float] = [], ec: [Float] = []
        let centers = HueSector.allCases.map { $0.center }, widths = HueSector.allCases.map { $0.width * 1.4 }
        for c in Self.checker {
            let lin = SIMD3(Self.srgbDecode(c.x / 255), Self.srgbDecode(c.y / 255), Self.srgbDecode(c.z / 255))
            let rgb = Spectral.xyzToRec2020.apply(Spectral.srgbToXYZ.apply(lin))
            let target = Self.oklab(stock.applyingLook(lin))
            let out = Self.oklab(simd_max(renderUniform(rgb, table: refTable, matrix: id, tone: t, balance: bal, neutral: nz), SIMD3(repeating: 1e-5)))
            let ct = (target.y * target.y + target.z * target.z).squareRoot() / max(target.x, 0.05)
            let co = (out.y * out.y + out.z * out.z).squareRoot() / max(out.x, 0.05)
            var ho = atan2(out.z, out.y) * 57.29578; if ho < 0 { ho += 360 }
            var dh = atan2(target.z, target.y) * 57.29578 - ho
            if dh > 180 { dh -= 360 }; if dh < -180 { dh += 360 }
            W.append((0..<7).map { k in
                var d = abs(ho - centers[k]); if d > 180 { d = 360 - d }
                let u = d / widths[k]
                return exp(-u * u)
            })
            let wgt = min(ct / 0.1, 1)          // trust saturated patches more
            eh.append(dh * wgt); ec.append(log(max(ct, 1e-3) / max(co, 1e-3)) * wgt)
            W[W.count - 1] = W[W.count - 1].map { $0 * wgt }
        }
        func ridge(_ e: [Float], lambda: Float) -> [Float] {
            var A = [[Float]](repeating: [Float](repeating: 0, count: 7), count: 7), b = [Float](repeating: 0, count: 7)
            for i in 0..<7 {
                for j in 0..<7 { A[i][j] = (0..<W.count).map { W[$0][i] * W[$0][j] }.reduce(0, +) }
                A[i][i] += lambda
                b[i] = (0..<W.count).map { W[$0][i] * e[$0] }.reduce(0, +)
            }
            return Self.solve(A, b) ?? [Float](repeating: 0, count: 7)
        }
        profileHue = ridge(eh, lambda: 0.15).map { min(max($0, -40), 40) }
        profileSat = ridge(ec, lambda: 0.15).map { min(max($0, -0.7), 0.7) }
    }

    /// Applies the scanner profile to a display-linear colour.
    @inline(__always) func profile(_ c: SIMD3<Float>) -> SIMD3<Float> {
        if measured != nil { return c }
        let lab = Self.oklab(simd_max(c, .zero))
        let C = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        if C < 1e-5 { return c }
        var h = atan2(lab.z, lab.y) * 57.29578; if h < 0 { h += 360 }
        var dh: Float = 0, ds: Float = 0
        for k in 0..<7 {
            var d = abs(h - FilmModel.sectorCenters[k]); if d > 180 { d = 360 - d }
            let u = d / FilmModel.sectorWidths[k]
            let w = exp(-u * u)
            dh += w * profileHue[k]; ds += w * profileSat[k]
        }
        let nh = (h + dh) * 0.017453293, nc = C * exp(ds)
        return Self.oklabToLinear(SIMD3(lab.x, nc * cos(nh), nc * sin(nh)))
    }
    static let sectorCenters = HueSector.allCases.map { $0.center }
    static let sectorWidths = HueSector.allCases.map { $0.width * 1.4 }

    static func oklabToLinear(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l2 = v.x + 0.3963377774 * v.y + 0.2158037573 * v.z
        let m2 = v.x - 0.1055613458 * v.y - 0.0638541728 * v.z
        let s2 = v.x - 0.0894841775 * v.y - 1.2914855480 * v.z
        let l3 = l2 * l2 * l2, m3 = m2 * m2 * m2, s3 = s2 * s2 * s2
        return SIMD3(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
                     -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
                     -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
    }

    /// Gaussian elimination for small dense systems.
    static func solve(_ a: [[Float]], _ b: [Float]) -> [Float]? {
        let n = b.count
        var m = a, v = b
        for c in 0..<n {
            guard let piv = (c..<n).max(by: { abs(m[$0][c]) < abs(m[$1][c]) }), abs(m[piv][c]) > 1e-12 else { return nil }
            m.swapAt(c, piv); v.swapAt(c, piv)
            for r in (c + 1)..<n {
                let f = m[r][c] / m[c][c]
                for k in c..<n { m[r][k] -= f * m[c][k] }
                v[r] -= f * v[c]
            }
        }
        var x = [Float](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            x[r] = (v[r] - ((r + 1)..<n).map { m[r][$0] * x[$0] }.reduce(0, +)) / m[r][r]
        }
        return x
    }

    @inline(__always) func luminance(_ c: SIMD3<Float>) -> Float { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    // MARK: Neutral balance

    func greyDensities(table: ExposureTable, tone t: Tone, ev: Float) -> SIMD3<Float> {
        let e = table.exposure(0.18, 0.18, 0.18) * pow(2, ev)
        var x = SIMD3<Float>.zero
        for k in 0..<3 { x[k] = log10(max(e[k], 1e-7)) - log10(Developer.midGrey) }
        let xp = uniformDIR(x, t)
        return SIMD3(density(xp.x, 0, t), density(xp.y, 1, t), density(xp.z, 2, t))
    }

    /// DIR inhibition for a uniform area (no spatial spread) — must match Developer.applyDIR.
    @inline(__always) func uniformDIR(_ x: SIMD3<Float>, _ t: Tone) -> SIMD3<Float> {
        if stock.kind == .blackWhite { return x }
        let same = stock.dirSame, inter = stock.dirInter
        let lo: Float = stock.kind == .slide ? -2.2 : t.toe, hi: Float = stock.kind == .slide ? 1.3 : t.shoulder
        let c = SIMD3(Developer.softClip(x.x, lo, hi), Developer.softClip(x.y, lo, hi), Developer.softClip(x.z, lo, hi))
        let k = 1 / (1 - same - 2 * inter)
        return SIMD3((x.x - same * c.x - inter * (c.y + c.z)) * k,
                     (x.y - same * c.y - inter * (c.x + c.z)) * k,
                     (x.z - same * c.z - inter * (c.x + c.y)) * k)
    }

    /// Printer lights (negatives) or dye balance (slides) that render grey densities `g` as neutral 18 %,
    /// plus the stock's intended colour cast.
    func solveNeutral(greyDensities g: SIMD3<Float>, withCast: Bool = true, targetY: Float = Developer.midGrey,
                      start: SIMD3<Float>? = nil, neutral nz: Neutralizer = .identity) -> SIMD3<Float> {
        let castOffset: SIMD3<Float>
        switch stock.kind {
        case .blackWhite:
            let z = Developer.logit(Developer.midGreyDensity / range) / paperKp
            return SIMD3(repeating: z + g.x)
        case .colorNegative: castOffset = withCast ? -stock.cast / stock.paperContrast : .zero
        case .slide: castOffset = withCast ? -stock.cast : .zero
        }
        let target = log10(max(targetY, 1e-5))
        var o: SIMD3<Float>
        if let start { o = start }
        else if stock.kind == .colorNegative {
            let lp = negToPrint!.sample(g)
            if !paperCurves.isEmpty {
                o = SIMD3(Self.tabInverse(paperCurves[0], 0.75), Self.tabInverse(paperCurves[1], 0.75), Self.tabInverse(paperCurves[2], 0.75)) - lp
            } else {
                o = SIMD3(repeating: Developer.logit(Developer.midGreyDensity / range) / paperKp) - lp
            }
        } else { o = .zero }
        func F(_ o: SIMD3<Float>) -> SIMD3<Float> {
            let c = render(g, balance: o, neutral: nz)
            return SIMD3(log10(max(c.x, 1e-6)), log10(max(c.y, 1e-6)), log10(max(c.z, 1e-6))) - target
        }
        for _ in 0..<30 {
            let r = F(o)
            if (r * r).sum() < 1e-10 { break }
            var J = [[Float]](repeating: [0, 0, 0], count: 3)
            for k in 0..<3 {
                var d = SIMD3<Float>.zero; d[k] = 1e-3
                let dr = (F(o + d) - r) / 1e-3
                for i in 0..<3 { J[i][k] = dr[i] }
            }
            guard let step = SpectralUpsampler.solve3(J, [r.x, r.y, r.z]) else { break }
            o -= simd_clamp(step, SIMD3(repeating: -0.5), SIMD3(repeating: 0.5))
        }
        return o + castOffset
    }

    /// Exposure table for a scene lit at `kelvin` (nil = light matching the film's balance).
    func table(kelvin: Float?) -> ExposureTable {
        guard let kelvin, abs(kelvin - stock.balanceKelvin) > 60 else { return refTable }
        let key = Int((kelvin / 50).rounded())
        sceneLock.lock(); defer { sceneLock.unlock() }
        if let t = sceneCache[key] { return t }
        let t = SpectralUpsampler.shared.exposureTable(sensitivities: sensitivities,
                                                        illuminant: Spectral.illuminant(kelvin: kelvin), reference: reference)
            .applying(hueCalibration)
        sceneCache[key] = t
        return t
    }

    /// How the lab prints this frame. Negatives: the printer always corrects overall density and removes
    /// `correction` of the scene-light colour cast. Slides: what you shot is what you get, apart from an
    /// optional scanner correction of the cast.
    func balance(scene: ExposureTable, tone t: Tone, ev: Float, correction: Float, neutral nz: Neutralizer,
                 densityEV: Float = 0) -> SIMD3<Float> {
        switch stock.kind {
        case .blackWhite:
            return solveNeutral(greyDensities: greyDensities(table: refTable, tone: t, ev: ev + densityEV))
        case .colorNegative:
            // The printer always corrects overall density (including reciprocity speed loss).
            let keepCast = solveNeutral(greyDensities: greyDensities(table: refTable, tone: t, ev: ev + densityEV), neutral: nz)
            let full = solveNeutral(greyDensities: greyDensities(table: scene, tone: t, ev: ev), neutral: nz)
            // keepCast prints the reference light neutral, so scene light through it shows its real cast.
            return keepCast + (full - keepCast) * correction
        case .slide:
            let base = solveNeutral(greyDensities: greyDensities(table: refTable, tone: t, ev: 0), neutral: nz)
            let full = solveNeutral(greyDensities: greyDensities(table: scene, tone: t, ev: 0), neutral: nz)
            return base + (full - base) * correction
        }
    }
}

public enum FilmDiagnostics {
    /// Human-readable dump of a stock's calibration (for the CLI).
    public static func report(_ stock: FilmStock) -> String {
        let m = FilmModel.model(for: stock)
        let t = m.tone(push: 0)
        let g = m.greyDensities(table: m.refTable, tone: t, ev: 0)
        let raw = m.solveNeutral(greyDensities: g)
        let nz = m.cachedNeutralizer(push: 0)
        let bal = m.balance(scene: m.refTable, tone: t, ev: 0, correction: 0, neutral: nz)
        var s = "hue calibration \(m.hueCalibration)\ngrey densities \(g)\nraw balance \(raw) -> \(m.render(g, balance: raw))\n"
        s += "balance \(bal) -> \(m.render(g, balance: bal, neutral: nz))\n"
        for c in 0..<3 { s += "neutralizer[\(c)] " + zip(nz.keys[c], nz.vals[c]).map { String(format: "%.2f:%.3f", $0, $1) }.joined(separator: " ") + "\n" }
        for d: Float in [0, 0.5, 1, 1.5, 2, 2.5, 3] { s += "D=\(d) -> \(m.display!.sample(SIMD3(repeating: d)))\n" }
        return s
    }
}

extension FilmDiagnostics {
    /// Hue error (degrees) and chroma ratio for each ColorChecker patch, raw model vs calibrated.
    public static func hueReport(_ stock: FilmStock) -> String {
        let m = FilmModel.model(for: stock)
        let t = m.tone(push: 0), nz = m.cachedNeutralizer(push: 0)
        let bal = m.solveNeutral(greyDensities: m.greyDensities(table: m.refTable, tone: t, ev: 0), withCast: false, neutral: nz)
        let id = Spectral.M3(r0: [1, 0, 0], r1: [0, 1, 0], r2: [0, 0, 1])
        let inv = m.hueCalibration
        var s = "patch        raw dh / C×   calibrated dh / C×\n"
        let names = ["dark skin", "light skin", "blue sky", "foliage", "blue flower", "bluish green", "orange", "purplish blue",
                     "moderate red", "purple", "yellow green", "orange yellow", "blue", "green", "red", "yellow", "magenta", "cyan"]
        for (i, c) in FilmModel.checker.enumerated() {
            let lin = SIMD3(FilmModel.srgbDecode(c.x / 255), FilmModel.srgbDecode(c.y / 255), FilmModel.srgbDecode(c.z / 255))
            let xyz = Spectral.srgbToXYZ.apply(lin), ref = Spectral.lab(xyz)
            let rgb = Spectral.xyzToRec2020.apply(xyz)
            func stats(_ table: ExposureTable, _ mat: Spectral.M3, profiled: Bool) -> (Float, Float) {
                var o = m.renderUniform(rgb, table: table, matrix: mat, tone: t, balance: bal, neutral: nz)
                if profiled { o = m.profile(o) }
                let lab = Spectral.lab(Spectral.srgbToXYZ.apply(simd_max(o, SIMD3(repeating: 1e-5))))
                var dh = atan2(lab.z, lab.y) - atan2(ref.z, ref.y)
                if dh > .pi { dh -= 2 * .pi }; if dh < -.pi { dh += 2 * .pi }
                return (dh * 57.3, (lab.y * lab.y + lab.z * lab.z).squareRoot() / max((ref.y * ref.y + ref.z * ref.z).squareRoot(), 1e-3))
            }
            let raw = stats(m.rawTable, id, profiled: false), cal = stats(m.refTable, id, profiled: true)
            _ = inv
            s += names[i].padding(toLength: 14, withPad: " ", startingAt: 0) + String(format: "%6.1f° %4.2f    %6.1f° %4.2f\n", raw.0, raw.1, cal.0, cal.1)
        }
        return s
    }

}

extension FilmDiagnostics {
    /// Renders an sRGB colour (8-bit) uniformly through a stock under a given scene light.
    /// Wide-gamut colours: linear-extrapolated vs physically valid spectral exposure, and the rendered result.
    public static func gamutReport(_ stock: FilmStock) -> String {
        let t0 = Date()
        let valid = SpectralUpsampler.shared.gamutSpectra.compactMap { $0 }.count
        var s = String(format: "gamut grid: %d valid spectra (%.1f s)\n", valid, Date().timeIntervalSince(t0))
        let m = FilmModel.model(for: stock)
        let t = m.tone(push: 0), nz = m.cachedNeutralizer(push: 0)
        let table = m.refTable
        let bal = m.balance(scene: table, tone: t, ev: 0, correction: 0, neutral: nz)
        let id = Spectral.M3(r0: [1, 0, 0], r1: [0, 1, 0], r2: [0, 0, 1])
        let p3ToXYZ = Spectral.M3(r0: [0.4865709, 0.2656677, 0.1982173], r1: [0.2289746, 0.6917385, 0.0792869], r2: [0, 0.0451134, 1.0439444])
        let cases: [(String, SIMD3<Float>)] = [
            ("sRGB red", Spectral.xyzToRec2020.apply(Spectral.srgbToXYZ.apply([0.5, 0, 0]))),
            ("P3 red", Spectral.xyzToRec2020.apply(p3ToXYZ.apply([0.5, 0, 0]))),
            ("P3 green", Spectral.xyzToRec2020.apply(p3ToXYZ.apply([0, 0.4, 0]))),
            ("P3 orange", Spectral.xyzToRec2020.apply(p3ToXYZ.apply([0.6, 0.25, 0]))),
            ("P3 cyan", Spectral.xyzToRec2020.apply(p3ToXYZ.apply([0, 0.35, 0.4]))),
            ("2020 red", [0.4, 0, 0]), ("2020 green", [0, 0.3, 0]), ("2020 blue", [0, 0, 0.5]),
            ("2020 teal", [0, 0.3, 0.3]), ("2020 violet", [0.15, 0, 0.5])]
        for (name, rgb) in cases {
            let lin = table.matrix.apply(rgb), spec = table.exposure(rgb.x, rgb.y, rgb.z)
            let o = m.profile(m.renderUniform(rgb, table: table, matrix: id, tone: t, balance: bal, neutral: nz))
            let enc = SIMD3(Developer.encode(o.x), Developer.encode(o.y), Developer.encode(o.z)) * 255
            s += String(format: "%-12@ linear E %6.3f %6.3f %6.3f  spectral E %6.3f %6.3f %6.3f  -> %3.0f %3.0f %3.0f\n",
                        name as NSString, lin.x, lin.y, lin.z, spec.x, spec.y, spec.z, enc.x, enc.y, enc.z)
        }
        // Skin: smooth-basis vs measured-skin film exposure (identical colour to the eye).
        let srgbToRec = Spectral.xyzToRec2020.compose(Spectral.srgbToXYZ)
        for (name, c8) in [("dark skin", SIMD3<Float>(115, 82, 68)), ("light skin", SIMD3<Float>(194, 150, 130)),
                           ("tan skin", SIMD3<Float>(170, 120, 90)), ("pale skin", SIMD3<Float>(232, 200, 185)),
                           ("deep skin", SIMD3<Float>(90, 60, 45)), ("orange", SIMD3<Float>(214, 126, 44))] {
            let lin = SIMD3(FilmModel.srgbDecode(c8.x / 255), FilmModel.srgbDecode(c8.y / 255), FilmModel.srgbDecode(c8.z / 255))
            let rgb = srgbToRec.apply(lin)
            let xyz = Spectral.srgbToXYZ.apply(lin), S = xyz.sum()
            let a = table.matrix.apply(rgb), b = table.exposure(rgb.x, rgb.y, rgb.z)
            let fx = SpectralUpsampler.srgbFix()
            let wt = SpectralPrior.skin.spectrum(xyz: xyz * fx.fix, weights: fx.w)?.weight ?? 0
            s += String(format: "%-10@ skin weight %.2f (xy distance %.1f)  E change R %+.1f%% G %+.1f%% B %+.1f%%\n", name as NSString,
                        wt, SpectralPrior.skin.distance(xyz.x / S, xyz.y / S), (b.x / a.x - 1) * 100, (b.y / a.y - 1) * 100, (b.z / a.z - 1) * 100)
        }
        // Continuity across the sRGB gamut boundary: grey -> P3 green.
        s += "sweep grey->P3 green (layer R exposure, the one that goes negative):"
        for k in 0...12 {
            let f = Float(k) / 12
            let rgb = Spectral.xyzToRec2020.apply(p3ToXYZ.apply(SIMD3<Float>(0.18, 0.18, 0.18) * (1 - f) + SIMD3<Float>(0, 0.4, 0) * f))
            s += String(format: " %.4f", table.exposure(rgb.x, rgb.y, rgb.z).x)
        }
        return s + "\n"
    }

    /// System MTF of the film (scatter + DIR adjacency effects), measured like a datasheet: low-contrast
    /// sine-wave exposures (±0.1 log E), response in effective log exposure, normalised at 1 cycle/mm.
    public static func mtf(_ stock: FilmStock, frequencies: [Float] = [1, 2, 5, 10, 15, 20, 30, 40, 60, 80, 100]) -> String {
        let w = 4096, h = 4
        var settings = DevelopSettings()
        settings.grain = 0; settings.halation = 0; settings.sceneLight = false
        let ctx = DevelopContext(fullLongSide: 36000)    // 1 µm per pixel on 35 mm
        var rows: [(Float, SIMD3<Float>)] = []
        for f in frequencies {
            var img = RGBImage(width: w, height: h)
            for y in 0..<h { for x in 0..<w {
                let v = 0.18 * pow(10, 0.1 * sin(2 * Float.pi * f * Float(x) / 1000))
                img.r[y * w + x] = v; img.g[y * w + x] = v; img.b[y * w + x] = v
            } }
            let out = Developer.develop(img, stock: stock, settings: settings, context: ctx)
            var amp = SIMD3<Float>.zero
            for c in 0..<3 {
                let plane = c == 0 ? out.r : c == 1 ? out.g : out.b
                var sa: Double = 0, ca: Double = 0, n: Double = 0, mean: Double = 0
                let lo = 1024, hi = 3072
                for x in lo..<hi { mean += Double(log10(max(FilmModel.srgbDecode(plane[2 * w + x]), 1e-6))) }
                mean /= Double(hi - lo)
                for x in lo..<hi {
                    let v = Double(log10(max(FilmModel.srgbDecode(plane[2 * w + x]), 1e-6))) - mean
                    let ph = 2 * Double.pi * Double(f) * Double(x) / 1000
                    sa += v * sin(ph); ca += v * cos(ph); n += 1
                }
                amp[c] = Float(2 * (sa * sa + ca * ca).squareRoot() / n)
            }
            rows.append((f, amp))
        }
        let ref = rows.first!.1
        var s = "cycles/mm   R      G      B   (% response)\n"
        for (f, a) in rows {
            let r = a / ref * 100
            s += String(format: "%5.0f   %5.0f  %5.0f  %5.0f\n", f, r.x, r.y, r.z)
        }
        return s
    }

    /// RMS granularity (×1000, 48 µm aperture) vs density: measured sub-emulsion model and the generic
    /// two-emulsion model, both calibrated to the datasheet value at D = 1.
    public static func granularity(_ stock: FilmStock) -> String {
        let m = FilmModel.model(for: stock)
        let s48 = stock.grainRMS
        var s = String(format: "%@: datasheet RMS %.1f at D=1\n  D     layered R/G/B          generic   (sub-emulsion fill R: fast/med/slow)\n", stock.displayName, s48)
        let dmax = m.layerDmax
        func generic(_ d: Float) -> Float {
            func v(_ d: Float) -> Float {
                let p = min(max(d / dmax, 0), 0.999), pf = 1 - (1 - p) * (1 - p), ps = p * p
                return pf * (1 - pf) + ps * (1 - ps) / 4
            }
            return s48 * (v(d) / v(1)).squareRoot()
        }
        for d in stride(from: Float(0.1), through: 2.5, by: 0.2) {
            var line = String(format: "%4.1f  ", d)
            if let g = m.grainLayers {
                for c in 0..<3 { line += String(format: "%5.1f ", s48 * (g.weights(c, d).sum() / g.weights(c, 1).sum()).squareRoot()) }
                let f = g.fill(0, d)
                line += String(format: "   %5.1f      %.2f/%.2f/%.2f", generic(d), f.x, f.y, f.z)
            } else { line += String(format: "  (no sub-emulsion data)   %5.1f", generic(d)) }
            s += line + "\n"
        }
        if let g = m.grainLayers { s += String(format: "relative crystal areas (R): %.2f / %.2f / %.2f\n", g.area[0].x, g.area[0].y, g.area[0].z) }
        return s
    }

    /// Grey-card layer exposures with a lens filter / redscale (relative to normal), for diagnostics.
    public static func techniqueReport(_ stock: FilmStock, filter: LensFilter, redscale: Bool) -> String {
        let m = FilmModel.model(for: stock)
        let a = m.refTable.exposure(0.18, 0.18, 0.18), b = m.table(kelvin: nil, filter: filter, redscale: redscale).exposure(0.18, 0.18, 0.18)
        let r = b / a
        return String(format: "grey exposure vs normal: R %.3f G %.3f B %.3f  (log %.2f %.2f %.2f)", r.x, r.y, r.z, log10(r.x), log10(r.y), log10(r.z))
    }

    public static func probe(_ stock: FilmStock, srgb: SIMD3<Float>, kelvin: Float?, correction: Float) -> SIMD3<Float> {
        let m = FilmModel.model(for: stock)
        let t = m.tone(push: 0), nz = m.cachedNeutralizer(push: 0)
        let table = m.table(kelvin: kelvin)
        let bal = m.balance(scene: table, tone: t, ev: 0, correction: correction, neutral: nz)
        let lin = SIMD3(FilmModel.srgbDecode(srgb.x / 255), FilmModel.srgbDecode(srgb.y / 255), FilmModel.srgbDecode(srgb.z / 255))
        let rgb = Spectral.xyzToRec2020.apply(Spectral.srgbToXYZ.apply(lin))
        let id = Spectral.M3(r0: [1, 0, 0], r1: [0, 1, 0], r2: [0, 0, 1])
        let o = m.profile(m.renderUniform(rgb, table: table, matrix: id, tone: t, balance: bal, neutral: nz))
        return SIMD3(Developer.encode(o.x), Developer.encode(o.y), Developer.encode(o.z)) * 255
    }
}

extension FilmDiagnostics {
    /// Stage-by-stage trace of one sRGB colour (8-bit) through a stock.
    public static func trace(_ stock: FilmStock, srgb: SIMD3<Float>) -> String {
        let m = FilmModel.model(for: stock)
        let t = m.tone(push: 0), nz = m.cachedNeutralizer(push: 0)
        let bal = m.balance(scene: m.refTable, tone: t, ev: 0, correction: 0, neutral: nz)
        let lin = SIMD3(FilmModel.srgbDecode(srgb.x / 255), FilmModel.srgbDecode(srgb.y / 255), FilmModel.srgbDecode(srgb.z / 255))
        let rgb = Spectral.xyzToRec2020.apply(Spectral.srgbToXYZ.apply(lin))
        let sp = SpectralUpsampler.shared.spectrum(srgb: lin)
        var s = "basis error \(SpectralUpsampler.shared.basisError())\nrec2020 \(rgb)\nspectrum " + stride(from: 0, to: Spectral.count, by: 4).map { String(format: "%.0f:%.2f", Spectral.wavelengths[$0], sp[$0]) }.joined(separator: " ") + "\n"
        let e = m.refTable.exposure(rgb.x, rgb.y, rgb.z)
        let x = SIMD3(log10(e.x), log10(e.y), log10(e.z)) - log10(Developer.midGrey)
        let xp = m.uniformDIR(x, t)
        let d = SIMD3(m.density(xp.x, 0, t), m.density(xp.y, 1, t), m.density(xp.z, 2, t))
        let grey = m.greyDensities(table: m.refTable, tone: t, ev: log2(SpectralUpsampler.lum(rgb) / 0.18))
        s += "exposure \(e)\nlogE rel \(x) -> after DIR \(xp)\nneg density \(d)   (grey of same lum \(grey))\n"
        if let lut = m.negToPrint {
            let lp = lut.sample(d)
            s += "print logE \(lp + bal)   grey \(lut.sample(grey) + bal)\n"
        }
        let out = m.render(d, balance: bal, neutral: nz)
        s += "display linear \(out)  -> sRGB \(SIMD3(Developer.encode(out.x), Developer.encode(out.y), Developer.encode(out.z)) * 255)\n"
        return s
    }
}

extension SpectralUpsampler {
    static func lum(_ rec2020: SIMD3<Float>) -> Float { Spectral.rec2020ToXYZ.apply(rec2020).y }
}

extension FilmDiagnostics {
    /// Grey ramp neutrality before/after the neutralizer for a given push.
    public static func rampReport(_ stock: FilmStock, push: Float) -> String {
        let m = FilmModel.model(for: stock)
        let t = m.tone(push: push), nz = m.cachedNeutralizer(push: push)
        let bal = m.balance(scene: m.refTable, tone: t, ev: -push, correction: 0, neutral: nz)
        var s = ""
        for ev in stride(from: Float(-6), through: 6, by: 1) {
            let g = m.greyDensities(table: m.refTable, tone: t, ev: ev - push)
            let c = m.render(g, balance: bal, neutral: nz)
            let lp = m.negToPrint.map { $0.sample(g) } ?? g
            s += String(format: "ev %+3.0f  D %.2f %.2f %.2f  key %.3f %.3f %.3f  off %.3f %.3f %.3f  out %.3f %.3f %.3f\n", ev, g.x, g.y, g.z,
                        lp.x, lp.y, lp.z, nz.offset(0, lp.x), nz.offset(1, lp.y), nz.offset(2, lp.z), c.x, c.y, c.z)
        }
        return s
    }
}
