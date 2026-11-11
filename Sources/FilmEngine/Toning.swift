import Foundation
import simd

// MARK: - B&W paper image tone and chemical toning

/// The image tone of a B&W paper, set by the size and shape of its developed silver.
public enum PaperTone: String, CaseIterable, Codable, Identifiable {
    case neutral, warm, cold
    public var id: String { rawValue }
    public var label: String {
        switch self { case .neutral: "Neutral black"; case .warm: "Warm-tone (cream base)"; case .cold: "Cold-tone" }
    }
}

/// After-treatment of a B&W print.
public enum Toner: String, CaseIterable, Codable, Identifiable {
    case none, selenium, sepia
    public var id: String { rawValue }
    public var label: String {
        switch self { case .none: "None"; case .selenium: "Selenium"; case .sepia: "Sepia (bleach & redevelop)" }
    }
}

/// Spectral rendering of a toned / tinted silver image: density × spectral shape of each image substance,
/// integrated under the D50 viewing light and adapted to a *perfect* white (so a cream base reads as
/// cream next to the mount, as it does in the hand).
///
/// Image substances (spectral densities normalised to unit luminance-weighted density, so tone changes
/// colour, not overall lightness):
/// - **Filamentary silver (neutral papers):** spectrally flat.
/// - **Fine silver (warm-tone papers, chlorobromide emulsions):** smaller grains absorb more strongly at
///   short wavelengths, a density rising toward the blue → brown-black.
/// - **Cold-tone papers:** slightly more red absorption → blue-black.
/// - **Silver sulfide (sepia):** a semiconductor (band gap ≈ 1 eV) whose absorption climbs steadily toward
///   the blue → yellow-brown. It covers less than metallic silver (D-max falls ≈ 10 %).
/// - **Silver selenide (selenium):** almost neutral with extra green absorption → a purple-brown cast in the
///   shadows, and *more* covering power (D-max rises ≈ 10 %, the archival printer's reason to use it).
///
/// Conversion by density: selenium attacks the densest silver first (shadows tone, highlights barely);
/// a sepia bleach attacks the finest, thinnest silver first, so a partial bleach browns the highlights and
/// mid-tones and leaves silver-black shadows — the classic split tone.
///
/// The spectral shapes are smooth approximations of the substances' published absorption behaviour, not
/// measured toner spectra.
struct BWTone {
    let table: [SIMD3<Float>]
    static let maxD: Float = 3.4, steps = 341

    static func silverShape(_ tone: PaperTone) -> [Float] {
        Spectral.wavelengths.map { l in
            switch tone {
            case .neutral: 1
            case .warm: pow(l / 560, -0.4)
            case .cold: pow(l / 560, 0.25)
            }
        }
    }
    static let sulfide: [Float] = Spectral.wavelengths.map { pow($0 / 560, -1.7) }
    static let selenide: [Float] = Spectral.wavelengths.map { 1 + 0.12 * Spectral.lobe($0, 545, 45, 45) + 0.05 * pow($0 / 560, -2) }

    /// Fraction of the silver converted at print density `d`.
    static func converted(_ toner: Toner, strength s: Float, d: Float) -> Float {
        switch toner {
        case .none: return 0
        case .selenium: let x = max(d, 0) / 1.2; return s * (1 - exp(-x * x))
        case .sepia:
            let depth = 0.15 + 2.6 * s     // density down to which the bleach has gone
            return 1 / (1 + exp((d - depth) / 0.18))
        }
    }

    init(paper: PaperTone, toner: Toner, strength: Float, flare: Float) {
        let n = Spectral.count
        let view = Spectral.d50
        let wY = (0..<n).map { Spectral.yBar[$0] * view[$0] }
        let wYs = wY.reduce(0, +)
        func normalised(_ s: [Float]) -> [Float] {
            let m = (0..<n).map { s[$0] * wY[$0] }.reduce(0, +) / wYs
            return s.map { $0 / m }
        }
        let silver = normalised(Self.silverShape(paper))
        let toned = normalised(toner == .sepia ? Self.sulfide : Self.selenide)
        let cover: Float = toner == .sepia ? 0.9 : 1.1
        // Warm-tone papers: cream baryta / base (a little blue absorption).
        let base: [Float] = Spectral.wavelengths.map { paper == .warm ? 0.022 * pow($0 / 450, -4) : 0 }
        func xyz(_ dens: [Float]) -> SIMD3<Float> {
            var spd = [Float](repeating: 0, count: n)
            for i in 0..<n { spd[i] = ((1 - flare) * pow(10, -dens[i]) + flare * pow(10, -base[i])) * view[i] }
            return Spectral.xyz(spd)
        }
        let white = Spectral.xyz(view)
        let scale = 1 / white.y
        let adapt = Spectral.adaptation(from: white * scale)
        table = (0..<Self.steps).map { k in
            let d = Self.maxD * Float(k) / Float(Self.steps - 1)
            let f = Self.converted(toner, strength: strength, d: d)
            let dens = (0..<n).map { i in base[i] + d * ((1 - f) * silver[i] + f * cover * toned[i]) }
            return Spectral.xyzToSRGB.apply(adapt(xyz(dens) * scale))
        }
    }

    @inline(__always) func sample(_ d: Float) -> SIMD3<Float> {
        let f = min(max(d, 0), Self.maxD) / Self.maxD * Float(Self.steps - 1)
        let i = min(Int(f), Self.steps - 2), t = f - Float(i)
        return table[i] * (1 - t) + table[i + 1] * t
    }

    private static var cache: [String: BWTone] = [:]
    private static let lock = NSLock()

    /// Nil for an untoned neutral print (rendered as an exact grey).
    static func cached(_ s: DevelopSettings, flare: Float) -> BWTone? {
        let toner = s.tonerStrength < 0.01 ? Toner.none : s.toner
        guard s.paperTone != .neutral || toner != .none else { return nil }
        let key = "\(s.paperTone.rawValue)|\(toner.rawValue)|\(Int((s.tonerStrength * 50).rounded()))"
        lock.lock(); defer { lock.unlock() }
        if let t = cache[key] { return t }
        let t = BWTone(paper: s.paperTone, toner: toner, strength: (s.tonerStrength * 50).rounded() / 50, flare: flare)
        cache[key] = t
        return t
    }
}
