import Foundation
import simd

extension FilmDiagnostics {
    /// Measured reflectance spectra (380…780 nm, 5 nm) vs the engine's reconstruction of the same colour:
    /// how much each film layer's exposure differs (%), with no filter and through a red 25 filter.
    /// `spectra`: name + 81 reflectance values per entry.
    public static func spectralCheck(_ stock: FilmStock, spectra: [(String, [Float])], verbose: Bool = false) -> String {
        let m = FilmModel.model(for: stock)
        let fx = SpectralUpsampler.srgbFix()
        let ill = m.reference, red = LensFilter.red25.transmittance
        let norms = (0..<3).map { k in (0..<Spectral.count).map { m.sensitivities[k][$0] * ill[$0] }.reduce(0, +) }
        func expo(_ r: [Float], _ t: [Float]?) -> SIMD3<Float> {
            var e = SIMD3<Float>.zero
            for k in 0..<3 {
                var a: Float = 0
                for l in 0..<Spectral.count { a += r[l] * ill[l] * (t?[l] ?? 1) * m.sensitivities[k][l] }
                e[k] = a / norms[k]
            }
            return e
        }
        var s = "", errs: [SIMD3<Float>] = [], smooth: [SIMD3<Float>] = [], errsRed: [Float] = [], wts: [Float] = []
        for (name, r) in spectra {
            let xyz = SpectralUpsampler.weights.indices.reduce(SIMD3<Float>.zero) { $0 + SpectralUpsampler.weights[$1] * r[$1] }
            let lin = Spectral.xyzToSRGB.apply(xyz / fx.fix)
            let rec = Spectral.xyzToRec2020.apply(xyz / fx.fix)
            let engine = m.refTable.exposure(rec.x, rec.y, rec.z)
            let truth = expo(r, nil)
            let recon = SpectralUpsampler.shared.spectrum(srgb: lin)
            let e = (engine / truth - 1) * 100
            smooth.append((m.refTable.matrix.apply(rec) / truth - 1) * 100)
            let S = xyz.sum()
            wts.append(SpectralPrior.best(x: xyz.x / S, y: xyz.y / S, xyz: xyz, weights: fx.w)?.weight ?? 0)
            // Red-filter exposure as the engine now sees it: blend of smooth basis and prior, as on the grid.
            let prior = SpectralPrior.best(x: xyz.x / S, y: xyz.y / S, xyz: xyz, weights: fx.w)
            let blended = prior.map { p in recon.indices.map { recon[$0] * (1 - p.weight) + p.spectrum[$0] * p.weight } } ?? recon
            let eRed = (expo(blended, red).x / expo(r, red).x - 1) * 100
            errs.append(e); errsRed.append(eRed)
            if verbose {
                s += String(format: "%-44@ sRGB %5.3f %5.3f %5.3f  exposure error R %+6.1f%% G %+6.1f%% B %+6.1f%%  red25 %+6.1f%%  wt %.2f\n",
                            String(name.prefix(44)) as NSString, lin.x, lin.y, lin.z, e.x, e.y, e.z, eRed, wts.last ?? 0)
            }
        }
        let n = Float(errs.count)
        let mean = errs.reduce(.zero, +) / n
        let rms = (errs.map { $0 * $0 }.reduce(.zero, +) / n).squareRoot()
        let redMean = errsRed.reduce(0, +) / n
        let sm = smooth.reduce(.zero, +) / n, smRms = (smooth.map { $0 * $0 }.reduce(.zero, +) / n).squareRoot()
        let wMean = wts.reduce(0, +) / n
        s += String(format: "%-13@ smooth R %+5.1f%% G %+5.1f%% B %+5.1f%% (rms %4.1f %4.1f %4.1f) -> engine R %+5.1f%% G %+5.1f%% B %+5.1f%% (rms %4.1f %4.1f %4.1f)  red25 %+5.1f%%  prior wt %.2f",
                    stock.id as NSString, sm.x, sm.y, sm.z, smRms.x, smRms.y, smRms.z, mean.x, mean.y, mean.z, rms.x, rms.y, rms.z, redMean, wMean)
        return s
    }
}

extension FilmDiagnostics {
    /// Which measured-material prior (if any) claims each ColorChecker patch and a grey ramp, and how strongly.
    public static func priorReport() -> String {
        let fx = SpectralUpsampler.srgbFix()
        let names = ["dark skin", "light skin", "blue sky", "foliage", "blue flower", "bluish green", "orange", "purplish blue",
                     "moderate red", "purple", "yellow green", "orange yellow", "blue", "green", "red", "yellow", "magenta", "cyan"]
        var rows: [(String, SIMD3<Float>)] = zip(names, FilmModel.checker).map { ($0, $1) }
        rows += [("white 243", [243, 243, 243]), ("grey 160", [160, 160, 160]), ("grey 122", [122, 122, 122]),
                 ("grey 85", [85, 85, 85]), ("grey 52", [52, 52, 52]), ("warm grey", [140, 130, 115]),
                 ("olive", [110, 110, 60]), ("khaki", [190, 180, 130]), ("mint", [150, 210, 160]), ("lime", [160, 220, 40])]
        var s = ""
        for (name, c8) in rows {
            let lin = SIMD3(FilmModel.srgbDecode(c8.x / 255), FilmModel.srgbDecode(c8.y / 255), FilmModel.srgbDecode(c8.z / 255))
            let xyz = Spectral.srgbToXYZ.apply(lin), S = xyz.sum()
            let parts = SpectralPrior.all.map { p -> String in
                let w = p.inRegion(xyz.x / S, xyz.y / S) ? (p.spectrum(xyz: xyz * fx.fix, weights: fx.w)?.weight ?? 0) : 0
                return String(format: "%@ %.2f", p.name, w)
            }
            s += String(format: "%-14@ ", name as NSString) + parts.joined(separator: "  ") + "\n"
        }
        return s
    }
}
