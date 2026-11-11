#!/usr/bin/env python3
"""Builds Sources/FilmEngine/FoliageData.swift from the USGS Spectral Library Version 7 vegetation chapter.

Source: R. F. Kokaly et al., "USGS Spectral Library Version 7", U.S. Geological Survey Data Series 1035
(2017), doi:10.3133/ds1035; data release doi:10.5066/F7RR1WDJ, file ASCIIdata_splib07a.zip.
USGS data is in the public domain (U.S. government work); the USGS is acknowledged as the source.

Selection: every measured (splib07a) spectrum in ChapterV_Vegetation from the ASD or Beckman
spectrometers that is *green vegetation* by a spectral test, not by name: a green reflectance peak over
the chlorophyll red well (R550 > 1.3 R670) and a strong red edge (R800 > 3 R670). This keeps green leaves,
needles, grass and green canopies and drops dry grass, bark, flowers, lichen, soil and water mixtures.
Samples labelled dry, dried, NPV (non-photosynthetic) or water are excluded as well.

Balance: the library holds many near-identical marsh plots; each plant group (first word of the sample
name) gets equal total weight, so common deep-green leaves and grass are as well represented as marsh.
Principal components are found in a wavelength-weighted space (weight 1 up to 700 nm, falling to 0.15 at
780 nm): beyond 700 nm the eye sees almost nothing, so XYZ cannot pin down the leaf's infrared plateau,
and letting it dominate the components would make the colour-constrained solve ill-conditioned.

Changes (derived statistics only; the raw spectra are not redistributed): spectra resampled to
380–780 nm in 5 nm steps (boxcar mean over each 5 nm bin), normalised to unit luminance (CIE Y under D65),
and reduced to a mean shape plus 3 principal components with their standard deviations; the CIE xy
chromaticities are summarised by their mean and covariance.

Usage: python3 -I scripts/convert_usgs_foliage.py <ASCIIdata_splib07a dir> Sources/FilmEngine/FoliageData.swift [dump.txt]
"""
import math, os, sys

WL = list(range(380, 781, 5))
BAD = -1e30


def lobe(l, m, s1, s2):
    t = (l - m) / (s1 if l < m else s2)
    return math.exp(-0.5 * t * t)


# Same analytic CIE 1931 fit and D65 as the engine (Spectral.swift).
XB = [1.056 * lobe(l, 599.8, 37.9, 31.0) + 0.362 * lobe(l, 442.0, 16.0, 26.7) - 0.065 * lobe(l, 501.1, 20.4, 26.2) for l in WL]
YB = [0.821 * lobe(l, 568.8, 46.9, 40.5) + 0.286 * lobe(l, 530.9, 16.3, 31.1) for l in WL]
ZB = [1.217 * lobe(l, 437.0, 11.8, 36.0) + 0.681 * lobe(l, 459.0, 26.0, 13.8) for l in WL]
D10 = [49.98, 54.65, 82.75, 91.49, 93.43, 86.68, 104.86, 117.01, 117.81, 114.86, 115.92, 108.81, 109.35, 107.80, 104.79, 107.69,
       104.41, 104.05, 100.00, 96.33, 95.79, 88.69, 90.01, 89.60, 87.70, 83.29, 83.70, 80.03, 80.21, 82.28, 78.28, 69.72, 71.61,
       74.35, 61.60, 69.89, 75.09, 63.59, 46.42, 66.81, 63.38]
D65 = []
for l in WL:
    x = (l - 380) / 10; i = min(int(x), 39); t = x - i
    D65.append(D10[i] * (1 - t) + D10[i + 1] * t)
WY = sum(d * y for d, y in zip(D65, YB))


def xyz(r):
    return [sum(r[i] * c[i] * D65[i] for i in range(len(WL))) / WY for c in (XB, YB, ZB)]


def read_column(path):
    with open(path, encoding="latin-1") as f:
        lines = f.read().split("\n")[1:]
    return [float(v) for v in lines if v.strip()]


def resample(wl_nm, vals):
    """Mean of valid samples within each 5 nm bin; linear interpolation where a bin has none."""
    out = []
    for c in WL:
        bin_ = [v for w, v in zip(wl_nm, vals) if c - 2.5 <= w < c + 2.5 and v > BAD]
        out.append(sum(bin_) / len(bin_) if bin_ else None)
    known = [(i, v) for i, v in enumerate(out) if v is not None]
    if len(known) < len(WL) * 0.8:
        return None
    for i in range(len(out)):
        if out[i] is None:
            lo = max((k for k in known if k[0] < i), default=None, key=lambda k: k[0])
            hi = min((k for k in known if k[0] > i), default=None, key=lambda k: k[0])
            if lo and hi:
                out[i] = lo[1] + (hi[1] - lo[1]) * (i - lo[0]) / (hi[0] - lo[0])
            else:
                out[i] = (lo or hi)[1]
    return out


def at(nm, wl_nm, vals):
    good = [(abs(w - nm), v) for w, v in zip(wl_nm, vals) if v > BAD and abs(w - nm) <= 10]
    return sum(v for _, v in good) / len(good) if good else None


def main(src, dst, dump=None):
    wl = {"ASD": [w * 1000 for w in read_column(os.path.join(src, "splib07a_Wavelengths_ASD_0.35-2.5_microns_2151_ch.txt"))],
          "BECK": [w * 1000 for w in read_column(os.path.join(src, "splib07a_Wavelengths_BECK_Beckman_0.2-3.0_microns.txt"))]}
    veg = os.path.join(src, "ChapterV_Vegetation")
    spectra, names = [], []
    for name in sorted(os.listdir(veg)):
        if not name.startswith("splib07a_") or "AREF" not in name:
            continue
        inst = "ASD" if "_ASD" in name else "BECK" if "_BECK" in name else None
        if inst is None:
            continue
        vals = read_column(os.path.join(veg, name))
        if len(vals) != len(wl[inst]):
            continue
        r550, r670, r800 = at(550, wl[inst], vals), at(670, wl[inst], vals), at(800, wl[inst], vals)
        if None in (r550, r670, r800) or r670 <= 0 or r550 < 1.3 * r670 or r800 < 3 * r670:
            continue
        low = name.lower()
        if any(k in low for k in ("dry", "dried", "npv", "water")):
            continue
        s = resample(wl[inst], vals)
        if s is None or min(s) < -0.01:
            continue
        spectra.append([max(v, 0.0) for v in s]); names.append(name)
    n, m = len(spectra), len(WL)
    shapes, xys = [], []
    for s in spectra:
        X, Y, Z = xyz(s)
        shapes.append([v / Y for v in s])
        xys.append((X / (X + Y + Z), Y / (X + Y + Z)))
    if dump:
        with open(dump, "w") as f:
            for nm_, s in zip(names, spectra):
                f.write(nm_.replace("splib07a_", "").replace("_AREF.txt", "") + " " + " ".join(f"{v:.5f}" for v in s) + "\n")
    groups = {}
    for nm_ in names:
        g = nm_.replace("splib07a_", "").split("_")[0]
        groups[g] = groups.get(g, 0) + 1
    wt = [1.0 / groups[nm_.replace("splib07a_", "").split("_")[0]] for nm_ in names]
    W = sum(wt)
    lw = [1.0 if l <= 700 else 1.0 - 0.85 * (l - 700) / 80 for l in WL]
    mean = [sum(w_ * s[i] for w_, s in zip(wt, shapes)) / W for i in range(m)]
    cent = [[(s[i] - mean[i]) * lw[i] for i in range(m)] for s in shapes]
    cov = [[sum(w_ * c[i] * c[j] for w_, c in zip(wt, cent)) / W for j in range(m)] for i in range(m)]
    total = sum(cov[i][i] for i in range(m))
    pcs, sig = [], []
    for k in range(3):
        v = [1.0 / math.sqrt(m)] * m
        for _ in range(500):
            w = [sum(cov[i][j] * v[j] for j in range(m)) for i in range(m)]
            for p in pcs:
                d = sum(a * b for a, b in zip(w, p)); w = [a - d * b for a, b in zip(w, p)]
            nrm = math.sqrt(sum(a * a for a in w)); v = [a / nrm for a in w]
        lam = sum(v[i] * sum(cov[i][j] * v[j] for j in range(m)) for i in range(m))
        pcs.append(v); sig.append(math.sqrt(max(lam, 0)))
        print(f"PC{k+1}: {100 * lam / total:.2f}% of weighted shape variance")
    # back to reflectance space (undo the wavelength weighting); sigma stays the component's spread
    pcs = [[v[i] / lw[i] for i in range(m)] for v in pcs]
    mx = sum(w_ * p[0] for w_, p in zip(wt, xys)) / W; my = sum(w_ * p[1] for w_, p in zip(wt, xys)) / W
    cxx = sum(w_ * (p[0] - mx) ** 2 for w_, p in zip(wt, xys)) / W; cyy = sum(w_ * (p[1] - my) ** 2 for w_, p in zip(wt, xys)) / W
    cxy = sum(w_ * (p[0] - mx) * (p[1] - my) for w_, p in zip(wt, xys)) / W
    print(f"{len(groups)} plant groups: " + ", ".join(f"{g} {c}" for g, c in sorted(groups.items())))
    f = lambda vals: "[" + ", ".join(f"{v:.6g}" for v in vals) + "]"
    out = f'''// GENERATED by scripts/convert_usgs_foliage.py — do not edit.
//
// Derived from the USGS Spectral Library Version 7 (Kokaly et al., U.S. Geological Survey Data Series 1035,
// 2017; doi:10.3133/ds1035, data doi:10.5066/F7RR1WDJ) — {n} green-vegetation spectra (leaves, needles,
// grass, canopies; each plant group weighted equally). Source: U.S. Geological Survey (public domain).
// Changes: resampled to 380–780 nm / 5 nm, normalised to unit luminance, reduced to a mean shape,
// 3 principal components and chromaticity statistics.

enum FoliageData {{
    /// Mean green-vegetation reflectance shape (unit CIE Y under D65), 380…780 nm step 5.
    static let mean: [Float] = {f(mean)}
    /// Principal components of the shape and their standard deviations across spectra.
    static let components: [[Float]] = [{", ".join(f(p) for p in pcs)}]
    static let sigma: [Float] = {f(sig)}
    /// CIE xy chromaticity of the spectra (D65): mean and covariance.
    static let xyMean: SIMD2<Float> = [{mx:.6f}, {my:.6f}]
    static let xyCov: [Float] = [{cxx:.6g}, {cxy:.6g}, {cyy:.6g}]
    static let samples = {n}
}}
'''
    open(dst, "w").write(out)
    print(f"{n} spectra, xy mean {mx:.4f} {my:.4f}, sd x {math.sqrt(cxx):.4f} y {math.sqrt(cyy):.4f}; wrote {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
