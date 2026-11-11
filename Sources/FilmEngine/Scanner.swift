import Foundation
import simd

/// How the lab turns a colour negative into a positive.
public enum LabProcess: String, CaseIterable, Codable, Identifiable {
    /// Optical RA-4 print: enlarger light through the negative onto colour paper.
    case print
    /// Minilab-style scan: narrow-band RGB light through the negative, digitally inverted channel by
    /// channel against a grey scale, with a scanner tone curve.
    case scan
    public var id: String { rawValue }
    public var label: String { self == .print ? "Optical print" : "Lab scan" }
}

/// Lab scanner model for colour negatives.
///
/// A scanner reads the negative through three narrow LED bands (≈ 450 / 540 / 650 nm), so it sees each
/// dye almost separately — much less crosstalk than paper, whose broad sensitivities overlap the dyes'
/// side absorptions. The software then inverts each channel independently, calibrated so a grey scale
/// comes out neutral at every density (what auto-balance does on a real minilab), and applies a gentler
/// tone curve than paper. The result is the familiar "scanned negative" look: flatter contrast, more
/// open shadows, highlights that roll off rather than burn, and colour set by the film's dyes and
/// interimage effects rather than by the paper.
final class ScanModel {
    let negToScan: LUT3
    /// Per channel: scan density (ascending) -> log10 output, from a grey ramp.
    let keys: [[Float]], vals: [[Float]]
    /// Scan densities of mid grey under the reference light at normal exposure.
    let mid: SIMD3<Float>

    /// Scanner LED bands (peak, half-widths) and its tone curve.
    static let bands: [(Float, Float, Float)] = [(650, 14, 16), (545, 15, 15), (450, 12, 14)]
    static let midSlope: Float = 1.12        // log-log contrast at mid grey (paper is ~1.6–1.8)
    static let blackLog: Float = log10(0.0035), whiteLog: Float = 0.12
    static let saturation: Float = 1.12      // scanner software's default colour boost

    init(model m: FilmModel, push: Float) {
        let dyes = m.measured?.dyes ?? m.stock.dyes.map { $0.sampled }
        let base = m.measured?.base ?? [Float](repeating: 0.15, count: Spectral.count)
        let ss = Self.bands.map { Spectral.band(peak: $0.0, left: $0.1, right: $0.2) }
        // Scan densities are relative to the film base (the scanner zeroes on clear film / orange mask).
        func scan(_ d: SIMD3<Float>, withBase: Bool) -> SIMD3<Float> {
            var out = SIMD3<Float>.zero
            for j in 0..<3 {
                var acc: Float = 0, norm: Float = 0
                for i in 0..<Spectral.count {
                    let dens = (withBase ? base[i] : 0) + d.x * dyes[0][i] + d.y * dyes[1][i] + d.z * dyes[2][i]
                    acc += pow(10, -dens) * ss[j][i]; norm += ss[j][i]
                }
                out[j] = -log10(max(acc / norm, 1e-9))
            }
            return out
        }
        let baseScan = scan(.zero, withBase: true)
        negToScan = LUT3(n: 33, maxIn: 3.2) { d in scan(d, withBase: true) - baseScan }

        let t = m.tone(push: push)
        mid = negToScan.sample(m.greyDensities(table: m.refTable, tone: t, ev: 0))
        // Target tone curve: logistic in log-log through mid grey with slope `midSlope`.
        let y0 = log10(Developer.midGrey)
        let p0 = (y0 - Self.blackLog) / (Self.whiteLog - Self.blackLog)
        let k = Self.midSlope / ((Self.whiteLog - Self.blackLog) * p0 * (1 - p0))
        let x0 = -Developer.logit(p0) / k
        func target(_ ev: Float) -> Float {
            let x = ev * log10(2)
            return Self.blackLog + (Self.whiteLog - Self.blackLog) * Developer.logistic(k * (x - x0))
        }
        var ks: [[Float]] = [[], [], []], vs: [[Float]] = [[], [], []]
        for i in 0...200 {
            let ev = -9 + Float(i) * 0.1
            let s = negToScan.sample(m.greyDensities(table: m.refTable, tone: t, ev: ev))
            let y = target(ev)
            for c in 0..<3 {
                // keep strictly increasing keys (density saturates in the toe / shoulder)
                if let last = ks[c].last, s[c] <= last + 1e-5 { continue }
                ks[c].append(s[c]); vs[c].append(y)
            }
        }
        keys = ks; vals = vs
    }

    @inline(__always) func invert(_ s: Float, _ c: Int) -> Float {
        let k = keys[c], v = vals[c]
        if s <= k[0] { return v[0] }
        if s >= k[k.count - 1] { return v[v.count - 1] }
        var lo = 0, hi = k.count - 1
        while hi - lo > 1 { let m = (lo + hi) >> 1; if k[m] <= s { lo = m } else { hi = m } }
        let f = (s - k[lo]) / max(k[hi] - k[lo], 1e-9)
        return v[lo] + (v[hi] - v[lo]) * f
    }

    /// Layer densities -> display-linear sRGB. `balance` is the per-channel scan-density correction.
    @inline(__always) func render(_ d: SIMD3<Float>, balance: SIMD3<Float>, fade: Fade? = nil) -> SIMD3<Float> {
        let s = negToScan.sample(fade.map { $0.apply(d) } ?? d) + balance
        var c = SIMD3(pow(10, invert(s.x, 0)), pow(10, invert(s.y, 1)), pow(10, invert(s.z, 2)))
        let y = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
        c = SIMD3(repeating: y) + (c - SIMD3(repeating: y)) * Self.saturation
        return c
    }
}

extension FilmModel {
    private static var scanCache: [String: ScanModel] = [:]
    private static let scanLock = NSLock()

    func scanModel(push: Float) -> ScanModel {
        let key = "\(stock.id)|\(Int((push * 10).rounded()))"
        Self.scanLock.lock()
        if let s = Self.scanCache[key] { Self.scanLock.unlock(); return s }
        Self.scanLock.unlock()
        let s = ScanModel(model: self, push: push)
        Self.scanLock.lock(); Self.scanCache[key] = s; Self.scanLock.unlock()
        return s
    }

    /// Scanner auto-balance: density is always normalised; `correction` of the scene-light cast is removed.
    func scanBalance(_ sm: ScanModel, scene: ExposureTable, tone t: Tone, ev: Float, correction: Float, densityEV: Float = 0, fade: Fade? = nil) -> SIMD3<Float> {
        // An old negative is scanned as it is now: auto-balance sees the faded grey.
        func f(_ d: SIMD3<Float>) -> SIMD3<Float> { fade.map { $0.apply(d) } ?? d }
        let keepCast = sm.mid - sm.negToScan.sample(f(greyDensities(table: refTable, tone: t, ev: ev + densityEV)))
        let full = sm.mid - sm.negToScan.sample(f(greyDensities(table: scene, tone: t, ev: ev + densityEV)))
        // Auto-balance normalises the overall density (mean of the channels) completely.
        let k = keepCast + (full - keepCast) * correction
        return k
    }
}
