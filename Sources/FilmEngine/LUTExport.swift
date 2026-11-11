import Foundation

/// 3D LUT export (Adobe / Resolve `.cube`) of a film's colour and tone.
///
/// Input is display-referred sRGB / Rec.709 (a camera JPEG or a graded video frame), as Emulsion 98 itself
/// treats JPEGs; output is sRGB. Every LUT entry is developed through the full engine — spectral
/// exposure, characteristic curves, DIR couplers, printing or scanning, paper — as a large uniform area,
/// so grain, halation, scatter and edge effects (which a LUT cannot hold) are left out.
public enum LUTExport {
    public static func cube(stock: FilmStock, settings: DevelopSettings, size n: Int = 33) -> String {
        let w = n * n, h = n
        var img = RGBImage(width: w, height: h)
        let toRec2020 = Spectral.xyzToRec2020.compose(Spectral.srgbToXYZ)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let i = b * n * n + g * n + r
            let e = SIMD3(Float(r), Float(g), Float(b)) / Float(n - 1)
            let lin = SIMD3(FilmModel.srgbDecode(e.x), FilmModel.srgbDecode(e.y), FilmModel.srgbDecode(e.z))
            let c = toRec2020.apply(lin)
            img.r[i] = c.x; img.g[i] = c.y; img.b[i] = c.z
        } } }
        var ctx = DevelopContext(fullLongSide: 3600, isDisplayReferred: true)
        ctx.uniform = true
        let out = Developer.develop(img, stock: stock, settings: settings, context: ctx)
        var s = "TITLE \"Emulsion 98 - \(stock.displayName)\"\n"
        s += "# Film emulation by Emulsion 98 (https://github.com/oddnebula/emulsion-98)\n"
        s += "# Input: display-referred sRGB / Rec.709. Output: sRGB. Colour and tone only (no grain or halation).\n"
        s += "LUT_3D_SIZE \(n)\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n"
        s.reserveCapacity(s.count + n * n * n * 24)
        for i in 0..<(n * n * n) {   // red changes fastest, as the format requires
            s += String(format: "%.6f %.6f %.6f\n", min(max(out.r[i], 0), 1), min(max(out.g[i], 0), 1), min(max(out.b[i], 0), 1))
        }
        return s
    }

    /// Applies a LUT (from `cube`) to display-referred sRGB values (trilinear), for verification.
    public static func apply(_ text: String, r: Float, g: Float, b: Float) -> SIMD3<Float> {
        let t = parsed(text)
        let n = t.n
        func at(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> { t.v[k * n * n + j * n + i] }
        let f = SIMD3(r, g, b) * Float(n - 1)
        let i0 = SIMD3<Int>(Int(min(f.x, Float(n - 2))), Int(min(f.y, Float(n - 2))), Int(min(f.z, Float(n - 2))))
        let d = f - SIMD3(Float(i0.x), Float(i0.y), Float(i0.z))
        var c = SIMD3<Float>.zero
        for dz in 0...1 { for dy in 0...1 { for dx in 0...1 {
            let wgt = (dx == 1 ? d.x : 1 - d.x) * (dy == 1 ? d.y : 1 - d.y) * (dz == 1 ? d.z : 1 - d.z)
            c += at(i0.x + dx, i0.y + dy, i0.z + dz) * wgt
        } } }
        return c
    }
    nonisolated(unsafe) private static var parseCache: (String, (n: Int, v: [SIMD3<Float>]))?
    private static func parsed(_ text: String) -> (n: Int, v: [SIMD3<Float>]) {
        if let c = parseCache, c.0 == text { return c.1 }
        var n = 33; var v: [SIMD3<Float>] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("LUT_3D_SIZE") { n = Int(line.split(separator: " ")[1]) ?? 33; continue }
            guard let first = line.first, first.isNumber || first == "-" || first == "." else { continue }   // skip keywords
            let p = line.split(separator: " ").compactMap { Float($0) }
            if p.count == 3 { v.append(SIMD3(p[0], p[1], p[2])) }
        }
        parseCache = (text, (n, v))
        return (n, v)
    }

    /// Safe file name for a stock's LUT.
    public static func fileName(_ stock: FilmStock, suffix: String = "") -> String {
        let base = "Emulsion98_\(stock.maker)_\(stock.name)\(suffix)".replacingOccurrences(of: " ", with: "_")
        return base.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } + ".cube"
    }
}
