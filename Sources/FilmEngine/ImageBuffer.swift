import Foundation
import Accelerate

/// Planar float RGB image. Values are linear light unless stated otherwise.
public struct RGBImage {
    public let width: Int
    public let height: Int
    public var r: [Float]
    public var g: [Float]
    public var b: [Float]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let n = width * height
        r = [Float](repeating: 0, count: n)
        g = r
        b = r
    }

    public init(width: Int, height: Int, r: [Float], g: [Float], b: [Float]) {
        self.width = width; self.height = height
        self.r = r; self.g = g; self.b = b
    }

    public var longSide: Int { max(width, height) }

    /// Copy of a rectangular region (clamped to bounds).
    public func cropped(x: Int, y: Int, width cw: Int, height ch: Int) -> RGBImage {
        let x0 = max(0, min(x, width - 1)), y0 = max(0, min(y, height - 1))
        let w = max(1, min(cw, width - x0)), h = max(1, min(ch, height - y0))
        var out = RGBImage(width: w, height: h)
        for yy in 0..<h {
            let s = (y0 + yy) * width + x0, d = yy * w
            for xx in 0..<w {
                out.r[d + xx] = r[s + xx]; out.g[d + xx] = g[s + xx]; out.b[d + xx] = b[s + xx]
            }
        }
        return out
    }

    /// Area-average downscale so the long side is at most `maxLong`.
    public func downscaled(toLongSide maxLong: Int) -> RGBImage {
        let f = Int((Float(longSide) / Float(max(1, maxLong))).rounded(.up))
        if f <= 1 { return self }
        let w = width / f, h = height / f
        var out = RGBImage(width: w, height: h)
        let inv = 1 / Float(f * f)
        let src = self
        out.r.withUnsafeMutableBufferPointer { orp in
        out.g.withUnsafeMutableBufferPointer { ogp in
        out.b.withUnsafeMutableBufferPointer { obp in
            let orr = orp.baseAddress!, og = ogp.baseAddress!, ob = obp.baseAddress!
            Parallel.rows(h) { ys in
                for y in ys {
                    for x in 0..<w {
                        var sr: Float = 0, sg: Float = 0, sb: Float = 0
                        for dy in 0..<f {
                            let base = (y * f + dy) * src.width + x * f
                            for dx in 0..<f {
                                sr += src.r[base + dx]; sg += src.g[base + dx]; sb += src.b[base + dx]
                            }
                        }
                        let i = y * w + x
                        orr[i] = sr * inv; og[i] = sg * inv; ob[i] = sb * inv
                    }
                }
            }
        }}}
        return out
    }
}

enum Parallel {
    static let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)

    /// Splits 0..<count into chunks and runs them concurrently.
    static func rows(_ count: Int, _ body: (Range<Int>) -> Void) {
        if count <= 0 { return }
        let chunks = min(count, cores * 4)
        let per = (count + chunks - 1) / chunks
        DispatchQueue.concurrentPerform(iterations: chunks) { i in
            let a = i * per, b = min(count, a + per)
            if a < b { body(a..<b) }
        }
    }
}

enum Blur {
    /// Gaussian blur of a single plane. Direct kernel for small sigma, 3-box approximation for large.
    static func gaussian(_ src: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
        if sigma < 0.3 { return src }
        if sigma < 3 { return separable(src, w, h, sigma: sigma) }
        var a = src
        var tmp = [Float](repeating: 0, count: src.count)
        for r in boxRadii(sigma: sigma, n: 3) {
            boxH(a, &tmp, w, h, r)
            boxV(tmp, &a, w, h, r)
        }
        return a
    }

    static func boxRadii(sigma: Float, n: Int) -> [Int] {
        let wIdeal = (12 * sigma * sigma / Float(n) + 1).squareRoot()
        var wl = Int(wIdeal.rounded(.down))
        if wl % 2 == 0 { wl -= 1 }
        let wu = wl + 2
        let mIdeal = (12 * sigma * sigma - Float(n * wl * wl) - Float(4 * n * wl) - Float(3 * n)) / Float(-4 * wl - 4)
        let m = Int(mIdeal.rounded())
        return (0..<n).map { (($0 < m ? wl : wu) - 1) / 2 }
    }

    static func boxH(_ src: [Float], _ dst: inout [Float], _ w: Int, _ h: Int, _ r: Int) {
        if r <= 0 { dst = src; return }
        let inv = 1 / Float(2 * r + 1)
        src.withUnsafeBufferPointer { sp in
        dst.withUnsafeMutableBufferPointer { dp in
            let s = sp.baseAddress!, d = dp.baseAddress!
            Parallel.rows(h) { ys in
                let wm = w - 1
                for y in ys {
                    let row = s + y * w, out = d + y * w
                    var acc = Float(r) * row[0]
                    for j in 0..<r { acc += row[min(j, wm)] }
                    for x in 0..<w {
                        acc += row[min(x + r, wm)]
                        out[x] = acc * inv
                        acc -= row[max(x - r, 0)]
                    }
                }
            }
        }}
    }

    static func boxV(_ src: [Float], _ dst: inout [Float], _ w: Int, _ h: Int, _ r: Int) {
        if r <= 0 { dst = src; return }
        let inv = 1 / Float(2 * r + 1)
        src.withUnsafeBufferPointer { sp in
        dst.withUnsafeMutableBufferPointer { dp in
            let s = sp.baseAddress!, d = dp.baseAddress!
            Parallel.rows(w) { xs in
                let n = xs.count, x0 = xs.lowerBound, hm = h - 1
                var acc = [Float](repeating: 0, count: n)
                for i in 0..<n {
                    let x = x0 + i
                    var a = Float(r) * s[x]
                    for j in 0..<r { a += s[min(j, hm) * w + x] }
                    acc[i] = a
                }
                for y in 0..<h {
                    let add = s + min(y + r, hm) * w + x0
                    let sub = s + max(y - r, 0) * w + x0
                    let out = d + y * w + x0
                    for i in 0..<n {
                        acc[i] += add[i]
                        out[i] = acc[i] * inv
                        acc[i] -= sub[i]
                    }
                }
            }
        }}
    }

    static func separable(_ src: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
        let rad = max(1, Int((sigma * 3).rounded(.up)))
        var k = [Float](repeating: 0, count: 2 * rad + 1)
        var sum: Float = 0
        for i in -rad...rad {
            let v = exp(-Float(i * i) / (2 * sigma * sigma))
            k[i + rad] = v; sum += v
        }
        for i in 0..<k.count { k[i] /= sum }
        var tmp = [Float](repeating: 0, count: src.count)
        var out = [Float](repeating: 0, count: src.count)
        src.withUnsafeBufferPointer { sp in
        tmp.withUnsafeMutableBufferPointer { tp in
        k.withUnsafeBufferPointer { kp in
            let s = sp.baseAddress!, t = tp.baseAddress!, kk = kp.baseAddress!
            Parallel.rows(h) { ys in
                for y in ys {
                    let row = s + y * w, o = t + y * w
                    for x in 0..<w {
                        var acc: Float = 0
                        if x >= rad && x < w - rad {
                            let base = row + x - rad
                            for i in 0...(2 * rad) { acc += base[i] * kk[i] }
                        } else {
                            for i in -rad...rad { acc += row[min(max(x + i, 0), w - 1)] * kk[i + rad] }
                        }
                        o[x] = acc
                    }
                }
            }
        }}}
        tmp.withUnsafeBufferPointer { tp in
        out.withUnsafeMutableBufferPointer { op in
        k.withUnsafeBufferPointer { kp in
            let t = tp.baseAddress!, o0 = op.baseAddress!, kk = kp.baseAddress!
            Parallel.rows(h) { ys in
                for y in ys {
                    let o = o0 + y * w
                    for i in -rad...rad {
                        let row = t + min(max(y + i, 0), h - 1) * w
                        let kv = kk[i + rad]
                        for x in 0..<w { o[x] += row[x] * kv }
                    }
                }
            }
        }}}
        return out
    }
}

enum Noise {
    @inline(__always) static func hash(_ v: UInt32) -> UInt32 {
        var x = v
        x ^= x >> 16; x &*= 0x7feb352d
        x ^= x >> 15; x &*= 0x846ca68b
        x ^= x >> 16
        return x
    }

    /// Unit-variance white Gaussian noise keyed on absolute pixel coordinates,
    /// so a crop renders the exact same grain as the full frame.
    static func white(_ w: Int, _ h: Int, originX: Int, originY: Int, seed: UInt32, channel: UInt32) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        out.withUnsafeMutableBufferPointer { op in
            let o = op.baseAddress!
            Parallel.rows(h) { ys in
                for y in ys {
                    let gy = UInt32(truncatingIfNeeded: y + originY)
                    let rowKey = hash(gy &* 0x85EBCA77 &+ seed &* 0x27D4EB2F &+ channel &* 0xC2B2AE3D)
                    for x in 0..<w {
                        let gx = UInt32(truncatingIfNeeded: x + originX)
                        var hh = hash(gx &* 0x9E3779B1 ^ rowKey)
                        let u1 = (Float(hh >> 8) + 0.5) * (1.0 / 16777216.0)
                        hh = hash(hh &+ 0x632BE5AB)
                        let u2 = Float(hh >> 8) * (1.0 / 16777216.0)
                        o[y * w + x] = (-2 * log(u1)).squareRoot() * cos(6.2831853 * u2)
                    }
                }
            }
        }
        return out
    }

    static func normalize(_ a: inout [Float]) {
        var mean: Float = 0, ms: Float = 0
        vDSP_meanv(a, 1, &mean, vDSP_Length(a.count))
        var neg = -mean
        vDSP_vsadd(a, 1, &neg, &a, 1, vDSP_Length(a.count))
        vDSP_measqv(a, 1, &ms, vDSP_Length(a.count))
        var s = 1 / max(ms.squareRoot(), 1e-6)
        vDSP_vsmul(a, 1, &s, &a, 1, vDSP_Length(a.count))
    }

    /// Film-grain field: fine grain plus larger clumps, unit variance.
    static func grain(_ w: Int, _ h: Int, originX: Int, originY: Int, seed: UInt32, channel: UInt32, sizePx: Float) -> [Float] {
        let white = Noise.white(w, h, originX: originX, originY: originY, seed: seed, channel: channel)
        var fine = Blur.gaussian(white, w, h, sigma: sizePx * 0.45)
        var clump = Blur.gaussian(white, w, h, sigma: sizePx * 1.4)
        normalize(&fine); normalize(&clump)
        var out = [Float](repeating: 0, count: w * h)
        var a: Float = 0.9, b: Float = 0.35
        vDSP_vsmul(fine, 1, &a, &out, 1, vDSP_Length(out.count))
        vDSP_vsma(clump, 1, &b, out, 1, &out, 1, vDSP_Length(out.count))
        normalize(&out)
        return out
    }
}

extension RGBImage {
    /// Resampled to exactly `w`×`h`, scaled to fill and centre-cropped (aspect preserved), bilinear after an
    /// area pre-reduction. Used to register a second exposure on the first frame.
    public func filled(width w: Int, height h: Int) -> RGBImage {
        if width == w && height == h { return self }
        let scale = max(Float(w) / Float(width), Float(h) / Float(height))
        var src = self
        let reduce = Int((1 / scale).rounded(.down))
        if reduce >= 2 { src = downscaled(toLongSide: max(longSide / reduce, 1)) }
        let s = max(Float(w) / Float(src.width), Float(h) / Float(src.height))
        let ox = (Float(src.width) * s - Float(w)) / 2, oy = (Float(src.height) * s - Float(h)) / 2
        var out = RGBImage(width: w, height: h)
        for y in 0..<h {
            let fy = min(max((Float(y) + 0.5 + oy) / s - 0.5, 0), Float(src.height - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, src.height - 1), ty = fy - Float(y0)
            for x in 0..<w {
                let fx = min(max((Float(x) + 0.5 + ox) / s - 0.5, 0), Float(src.width - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, src.width - 1), tx = fx - Float(x0)
                let i00 = y0 * src.width + x0, i01 = y0 * src.width + x1, i10 = y1 * src.width + x0, i11 = y1 * src.width + x1
                func bl(_ p: [Float]) -> Float {
                    (p[i00] * (1 - tx) + p[i01] * tx) * (1 - ty) + (p[i10] * (1 - tx) + p[i11] * tx) * ty
                }
                let o = y * w + x
                out.r[o] = bl(src.r); out.g[o] = bl(src.g); out.b[o] = bl(src.b)
            }
        }
        return out
    }
}
