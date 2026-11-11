<p align="center">
  <img src="docs/images/banner.png" alt="Emulsion 98 – spectral film simulation app for macOS" width="100%">
</p>

<h1 align="center">Emulsion 98 · Film Simulation for Mac</h1>

<p align="center">
  <b>A physically based film emulation darkroom for macOS.</b><br>
  Develop RAW, JPEG and HEIC photos through spectral simulations of Kodak, Fujifilm, Ilford and CineStill film, with real film grain, halation, push processing, cross-processing and redscale. It runs in a hand-drawn late-90s Mac OS 8 "Platinum" interface and plugs into Apple Photos.
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-555555?style=flat-square&logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="23 film stocks" src="https://img.shields.io/badge/film%20stocks-23-6666CC?style=flat-square">
  <img alt="Apple Photos extension" src="https://img.shields.io/badge/Apple%20Photos-extension-DDDDDD?style=flat-square">
  <img alt="MIT licence" src="https://img.shields.io/badge/code-MIT-999999?style=flat-square">
</p>

<p align="center">
  <a href="#-read-me-first">Read Me</a> ·
  <a href="#-film-stocks">Film stocks</a> ·
  <a href="#-darkroom-techniques">Techniques</a> ·
  <a href="#-how-the-film-simulation-works">How it works</a> ·
  <a href="#-film-luts-for-final-cut-resolve-photoshop-and-lightroom">LUTs</a> ·
  <a href="#-apple-photos">Apple Photos</a> ·
  <a href="#-installation">Install</a> ·
  <a href="#-faq">FAQ</a>
</p>

<p align="center">
  <img src="docs/images/window.jpg" alt="Emulsion 98 main window: film stock list, developed photo in Kodak Portra 400, darkroom controls and 1:1 grain loupe" width="100%">
</p>

---

## ▸ Read Me First

Most "film filters" are a colour lookup table and a grain overlay. **Emulsion 98 simulates the film itself.** Every pixel becomes a light spectrum, which is exposed onto each film layer's measured spectral sensitivity and developed through the stock's measured characteristic curves, couplers and grain statistics. Negatives are then printed on simulated paper under an enlarger lamp. The result reacts like film: overexposure, mixed light, tungsten bulbs, a red filter on Tri-X, a pushed roll of Portra 800 or a ten-year-old expired roll all behave the way they would on film.

- 🎞 **23 film stocks:** Kodak Portra 160 / 400 / 800, Ektar 100, Gold 200, UltraMax 400, ColorPlus 200, Vision3 250D, Ektachrome E100, Kodachrome 64, Tri-X 400, T-Max 100 · Fujifilm Pro 400H, Superia X-TRA 400, C200, Velvia 100, Provia 100F, Astia 100F, Acros 100 II · Ilford HP5 Plus, FP4 Plus, Delta 3200 · CineStill 800T
- 🔬 **Measured data, not presets:** 15 stocks and all 3 papers use digitised datasheet spectra and curves, skin tones use NIST's measured human-skin spectra, and foliage uses USGS measured leaf and canopy spectra (see *Credits*).
- 🌫 **Real film grain** from crystal statistics of each layer's fast, medium and slow sub-emulsions, so underexposed negatives look grainy and overexposed ones look fine, as on real film.
- 🔴 **Halation**, emulsion scatter and DIR-coupler edge effects, with CineStill's red glow around highlights.
- 📷 **Camera-aware RAW pipeline**, tuned for the Panasonic Lumix LX5 and working with about 940 cameras through Apple's RAW engine. It reads the as-shot white balance, so daylight film really goes amber under tungsten.
- 🧪 **Darkroom techniques:** push/pull, lab scan or optical print, lens filters, cross-processing, redscale, stand development, expired film and reciprocity failure.
- 🖼 **Apple Photos integration:** browse and import from your library (RAW originals preferred), save to an album, or use the **Photos editing extension** inside Photos itself, non-destructively.
- 💾 **A genuine late-90s Mac experience:** WindowShade, Balloon Help, Control Strip, extensions parade, Darkroom Saver, Sad Camera. All artwork and sounds are original.

## ▸ Film Stocks

<p align="center">
  <img src="docs/images/film-stocks.jpg" alt="Film simulation comparison: the same photo in Kodak Portra 400, Ektar 100, Gold 200, Fujifilm Superia 400, CineStill 800T, Vision3 250D, Ektachrome E100, Velvia 100, Kodachrome 64, Tri-X 400, Ilford HP5 Plus and Fujifilm Acros 100 II" width="100%">
</p>

| Type | Stocks |
|---|---|
| **Colour negative** | Kodak Portra 160 · Portra 400 · Portra 800 · Ektar 100 · Gold 200 · UltraMax 400 · ColorPlus 200 · Vision3 250D · Fujifilm Pro 400H · Superia X-TRA 400 · Fujicolor C200 · CineStill 800T |
| **Slide (reversal)** | Kodak Ektachrome E100 · Kodachrome 64 · Fujifilm Velvia 100 · Provia 100F · Astia 100F |
| **Black & white** | Kodak Tri-X 400 · T-Max 100 · Ilford HP5 Plus · FP4 Plus · Delta 3200 · Fujifilm Neopan Acros 100 II |

<p align="center">
  <img src="docs/images/detail.jpg" alt="1:1 crops: CineStill 800T red halation around a backlit figure, Portra 800 colour film grain, Tri-X 400 black and white film grain" width="100%">
</p>

<p align="center">
  <img src="docs/images/latitude.jpg" alt="Colour negative exposure latitude: Portra 400 underexposed two stops, normal, and overexposed two stops" width="100%">
  <br><sub>Exposure latitude: Portra 400 at −2, 0 and +2 stops. The lab prints each one normally, so the thin negative shows coarse grain and muddy shadows, and the dense one stays clean.</sub>
</p>

## ▸ Darkroom Techniques

<p align="center">
  <img src="docs/images/techniques.jpg" alt="Film techniques: original photo, Tri-X with a red 25 filter, stand development, Velvia cross-processed in C-41, Portra redscale, Portra 20 years expired" width="100%">
</p>

| Technique | What is simulated |
|---|---|
| **Push / pull** | Rated speed change with longer or shorter development. Measured push +1 and +2 curves where they exist (Portra 800). |
| **Optical print vs lab scan** | RA-4 paper printing under a tungsten-halogen enlarger, or a minilab-style RGB scanner with per-channel inversion, scanner optics and the lab's unsharp mask. |
| **Darkroom printing** | Dichroic Y/M filtration in CC units, print exposure, and pre-flashing to hold highlight detail. |
| **Multigrade B&W paper** | Grades 00–5, set by the blue:green split of the enlarger light between a hard and a soft emulsion. Colour-head Y/M work on B&W too. |
| **Lens filters** | Yellow, orange, red, green and blue (Wratten 8–58), plus 85B, 80A, 81A and 82A, applied to the light *spectrum*, with through-the-lens metering. |
| **Cross-processing** | E-6 slide film in C-41: measured slide curves mirrored and printed without an orange mask. |
| **Redscale** | Film loaded backwards: light passes through the orange base and the layers in reverse order. |
| **Agitation** | Continuous, intermittent or stand development: developer exhaustion, edge effects, compensation and bromide drag. |
| **Expired film** | Per-layer speed loss, chemical fog and flatter contrast by storage (freezer to hot car), plus speed-dependent radiation fog. |
| **Formats** | Half frame, 35 mm, 6×4.5, 6×6, 6×7 and 4×5 sheet film. A bigger negative means finer grain and less halation relative to the picture. |
| **Enlarger** | The enlarging lens's blur (about 45 lp/mm at 50 % MTF) and corner falloff (corners get about 84 % of the light, so they print lighter, the opposite of camera vignetting). For B&W, a diffusion or condenser head: the condenser's Callier effect prints silver negatives about a grade harder, with crisper grain. |
| **Paper tone & toning (B&W)** | Neutral, warm-tone (cream base) or cold-tone paper, and selenium or sepia toning, rendered spectrally. Selenium converts the densest silver first (deeper, purple-brown shadows); a sepia bleach converts the thinnest silver first, so a short bleach gives the classic split tone. |
| **Paper surface** | Glossy, lustre or matte. Surface reflection sets the print's deepest black (about D-max 2.3, 2.0 and 1.6). |
| **Borders** | A filed negative carrier (rough black rebate on a white paper margin), or a full-frame scan of the strip with ISO 35 mm perforations (4.75 mm pitch) and edge printing. Added when you develop. |
| **Archival fading** | The finished print or slide ages for up to 80 years, in the dark or on display. Each dye fades at its own rate and leftover couplers turn the whites yellow, so old album prints go red, Ektachrome goes magenta, cine prints go pink and framed prints go cyan. For lab scans, the stored negative fades and is scanned as it is now. |
| **Reciprocity failure** | Schwarzschild law per layer, from the EXIF shutter speed. |
| **Scene light** | The film sees the real colour temperature from the RAW's white balance, and the lab corrects only part of it. |

<p align="center">
  <img src="docs/images/printing.jpg" alt="Darkroom printing simulation: Tri-X at grade 2 under a diffusion and a condenser enlarger, and at grade 5; Portra 400 printed with +15 yellow and +15 magenta filtration, and as a lab scan" width="100%">
  <br><sub>Printing: Tri-X at grade 2 under a diffusion head and a condenser (the Callier effect), and at grade 5 (top). Portra 400 with +15 Y and +15 M enlarger filtration, and as a lab scan (bottom).</sub>
</p>

<p align="center">
  <img src="docs/images/fading.jpg" alt="Archival fading simulation: a new Portra print, the same print after 40 years in an album and 40 years framed, Ektachrome and Kodachrome slides after decades in a box, and a faded Vision3 cine print" width="100%">
  <br><sub>Archival fading: a Portra print new, after 40 years in an album and 40 years on a wall (top). Ektachrome and Kodachrome after decades in a slide box, and a 50-year-old cine print (bottom).</sub>
</p>

<p align="center">
  <img src="docs/images/toning.jpg" alt="B&W paper tone and toning simulation on Ilford HP5: neutral, warm-tone and cold-tone paper; selenium toned, sepia split tone and full sepia" width="100%">
  <br><sub>B&W paper and toning: neutral, warm-tone and cold-tone paper (top); selenium, a short sepia bleach (split tone) and full sepia on warm-tone paper (bottom).</sub>
</p>

<p align="center">
  <img src="docs/images/borders.jpg" alt="Film borders: a full-frame 35mm scan with sprocket holes and edge printing on Portra 400, and a filed negative carrier print on matte paper with Tri-X" width="100%">
</p>

## ▸ How the Film Simulation Works

A spectral, physically based model of shooting, developing and printing film (`Sources/FilmEngine`).

<details>
<summary><b>1 · Camera RAW → scene light</b></summary>

Apple's RAW engine decodes into wide-gamut linear Rec.2020 with no tone curve, no local tone mapping and no digital sharpening. Lens correction and highlight recovery are on, and noise reduction is tuned per camera and ISO. The decoder also reads the as-shot white balance, which is the colour of the scene light. Scene-linear OpenEXR is also accepted.
</details>

<details>
<summary><b>2 · Spectral reconstruction and exposure</b></summary>

- Each pixel becomes a smooth, physically valid reflectance spectrum (spectral primary decomposition after Mallett & Yuksel 2019, 380–780 nm in 5 nm steps). Three bounded basis spectra sum to a flat white and reproduce the sRGB primaries to about 1e-5 in XYZ. This avoids the hidden deep-red and UV metamers that film would record but the eye ignores.
- **Wide-gamut colours** (P3 phone photos, saturated RAW colours) use a 128×128 chromaticity grid holding the closest physically valid spectrum (a Dykstra projection onto non-negative spectra with exact CIE XYZ). It is continuous across the sRGB gamut boundary.
- **Measured skin spectra:** skin-coloured pixels get a spectrum from the space of real human skin. That space is built from NIST's reference set of 100 measured subjects: a mean shape plus 2 principal components, which cover 98 % of the variation. The spectrum is solved to reproduce the pixel's exact XYZ and blended in by how typical it is of measured skin.
  - **Why it matters:** the colour is unchanged to the eye, but film sees real skin. On Portra 400, skin gets about 5–6 % more red-layer exposure and 6–9 % less blue than a generic smooth spectrum gives, which is where its warmth on skin comes from.
  - **Darker skin:** the NIST subjects under-represent darker skin, so the prior extends 3× further along the pigmentation (melanin) component than the measured spread. Darker skin is covered too, at about 55 % weight against 90 % for lighter skin.
- **Measured foliage spectra:** green-vegetation pixels get a spectrum from the space of real leaves. It is built from 64 green leaf, needle, grass and canopy spectra in the USGS Spectral Library 7, picked by a spectral test rather than by name, with each of the 25 plant groups weighted equally.
  - **Why it matters:** chlorophyll absorbs deeply at 670 nm, right where film's red layers peak, while the eye judges red mostly at 600–640 nm. A smooth spectrum fills that dip in. Against the measured spectra, it over-exposes the red layer by 8–20 % (Portra 400 +13 %, Velvia +17 %), which turns leaves olive-brown.
  - **With the prior:** the error drops to about +2–3 % on the spectra the prior was built from, and to about +4.6 % (from +11 %) on plant groups it never saw.
  - **What it leaves alone:** greys, sky, skin and saturated greens (more likely paint or plastic) are left to the smooth basis. Check with `emulsion-cli priors`.
- **Scene light:** the CIE daylight series (from S0/S1/S2, which reproduce D65 to 0.03 %) at 4500 K and above, a blackbody for tungsten at 3500 K and below. Films are referenced to the light in their datasheets: D55 for daylight stocks, 3200 K for tungsten.
- The spectrum is integrated against each layer's measured spectral sensitivity, including Fujifilm's fourth, cyan-sensitive layer.
</details>

<details>
<summary><b>3 · Optics: scatter and halation</b></summary>

Emulsion scatter uses a long-tailed PSF (a 4-Gaussian fit of the Frieser MTF 1/(1+(f/fc)²)) per layer: the deep red layer is 1.25× softer and the top blue layer 0.8×. Halation is light reflected from the base back into the red layer. It is energy-conserving, clipped highlights act as light sources, and its strength follows each datasheet's antihalation rating. Vision3's remjet stops it; CineStill glows.

**Sharpness budget.** A digital photo already carries its camera's blur (lens, anti-aliasing filter, demosaicing: about σ = 0.55 px for a raw file and 0.45 px for a sharpened camera JPEG). Simply adding film scatter on top would blur twice. Blurs add in quadrature, so each scatter lobe only adds what it has beyond the camera's blur. Where the camera is softer than the film, the excess also stands in for part of the enlarger or scanner lens.
- **Example, LX5 raw (10 MP, σ ≈ 5.4 µm at the film plane):** the green record's MTF error against Portra 400's film MTF falls from 11.3 to 3.4 points at frequencies the camera still resolves. Tri-X and CineStill improve about as much.
- **Very sharp films (Ektar, Velvia):** these improve less, because detail the camera never recorded cannot be restored.
- **Check it with:** `emulsion-cli mtf <stock> --camera-blur <µm>`.
</details>

<details>
<summary><b>4 · Development: DIR couplers, curves, agitation, ageing</b></summary>

- **DIR couplers:** inhibitors diffuse 15–30 µm. Same-layer inhibition gives edge effects; interlayer inhibition gives colour saturation.
- **Characteristic curves:** measured datasheet curves, with measured push curves where available.
- **Reciprocity:** the Schwarzschild exponent per layer.
- **Developer exhaustion:** activity a(x) = 1 − s·(K ∗ D̄)(x), where K is diffusion plus a one-sided bromide-drag tail. *Stand* development also compensates large dense areas. Reversal film is handled through its first developer.
- **Expired film:**
  - Chemical ageing is scaled by storage (freezer ×0.08, fridge ×0.3, room ×1, hot ×2.5).
  - Per decade at room temperature: about 1 stop of speed loss (blue layer fastest), chemical fog (+0.05 / 0.07 / 0.12 D for the red / green / blue layers) and 6 % less contrast.
  - Radiation fog grows with film speed regardless of temperature.
</details>

<details>
<summary><b>5 · Grain from sub-emulsion crystal statistics</b></summary>

- Each layer's three measured sub-emulsions (fast, medium and slow) fill one after another as exposure rises.
- Their density fluctuation follows the Nutting / Siedentopf relation for a binomial fill plus dye-cloud placement: σ² ∝ a·Dmax·[p(1−p) + 0.05 p] / A.
- Crystal areas come from the measured speed separation (area ∝ speed^½). Each layer is calibrated to the datasheet RMS granularity at D = 1 through a 48 µm aperture.
- Each sub-emulsion also has its own dye-cloud size and binomial skew. Pixels smaller than a dye cloud saturate at the cloud size (Selwyn's law).
</details>

<details>
<summary><b>6 · Printing, scanning and viewing</b></summary>

- **Optical print:** a 3200 K tungsten-halogen enlarger behind a KG3 heat filter shines through the negative's dye spectra and orange mask onto the measured paper sensitivities (Kodak Portra Endura, Fujifilm Crystal Archive Type II, or Kodak 2383 for cine stocks). Printer lights are solved automatically, as a lab does.
- **Printer's controls:** dichroic filtration acts on the paper's log exposures (+Y removes blue light, so the print goes bluer), and print exposure is in stops. **Pre-flash** adds a uniform sub-threshold exposure (a fraction of the paper's mid-scale exposure) that lifts dense highlights out of the paper's toe, and the printer re-sets exposure so mid grey is unchanged.
- **Variable-contrast B&W paper:** a blue-only hard emulsion and a green-sensitised soft emulsion (which keeps its native blue sensitivity), exposed by the enlarger lamp through Ilford-style grade filters or colour-head Y/M. The spectrally computed blue share of the exposure maps to the ISO paper range (R ≈ 180 at grade 00 to ≈ 50 at grade 5). Grade 2 reproduces the classic graded print.
- **Enlarger:** the paper's exposure is formed as light, so the enlarger acts on it before the paper responds. The enlarging lens blurs by σ ≈ 4.5 µm at the negative (MTF 50 % near 45 lp/mm, a good 6-element lens at f/8). Its relative illumination falls as cos²θ, about 84 % at the corners with the usual lens (focal length ≈ negative diagonal), which is what good enlarging lenses measure, so corners print lighter. Crops are placed in the full frame, so 1:1 views match the full print.
- **Callier effect (B&W):** silver grains scatter light as well as absorb it. A condenser head's collimated light loses the scattered part, so the effective printing density rises to D·(1 + 0.28·(1 − e<sup>−D/0.4</sup>)): Q ≈ 1.28 at medium and high density, less in thin shadows. The printer re-sets exposure for mid grey, and the print comes out about one grade harder (measured: between grade 3 and 3¼) with crisper grain. Dye images barely scatter, so colour heads and colour prints are unaffected.
- **B&W image tone and toning:** the print is rendered from the spectral density of its image substances under D50, adapted to a perfect white, so a cream base reads as cream. Each substance's spectrum is normalised to unit luminance density, so tone changes colour, not lightness.
  - **Papers:** filamentary silver on neutral papers is spectrally flat. Finer silver on warm-tone papers absorbs more toward the blue (brown-black, plus a cream base). Cold-tone papers are slightly blue-black.
  - **Selenium:** silver selenide covers ≈ 10 % more than silver, with extra green absorption. It converts the densest silver first, so the shadows deepen and turn purple-brown while the highlights barely change.
  - **Sepia:** silver sulfide absorbs strongly toward the blue and covers ≈ 10 % less. The bleach converts the thinnest silver first, so a partial bleach browns the highlights and mid-tones and leaves silver shadows (split tone).
  - The spectral shapes are smooth approximations of these substances' known absorption behaviour, not measured toner spectra.
- **Lab scan:** narrow-band RGB LEDs (650 / 545 / 450 nm), per-channel inversion against a grey scale, a scanner tone curve and a colour boost. Then the scanner's optics (≈ 3.5 µm blur, a 4000 dpi-class MTF) and the fixed unsharp mask minilabs apply (9 µm radius, on log luminance so it adds no colour fringes), which gives scans their crisp, grain-forward look.
- **Viewing:** dyes are integrated under D50 (ISO 3664), or a ≈ 5400 K projector for 2383, and Bradford-adapted to the paper or base white. First-surface reflection and glare are included (0.4 % for glossy paper), which limits print blacks to a visual density of about 2.3–2.5.
</details>

<details>
<summary><b>7 · Archival fading</b></summary>

- Applied to the final image dyes (print or slide), after the lab has balanced the fresh picture, so the fade is never corrected away.
- Each dye keeps a fraction e<sup>−r·t</sup> of its density (first-order dye loss), with its own rate per dye, material and keeping.
- **In the dark:** colour paper loses cyan first (prints go red), E-6 slides lose cyan and yellow (magenta), Eastmancolor cine prints lose cyan and yellow (pink), and Kodachrome barely changes (yellow is its weakest dye). Leftover couplers form a yellow stain that grows and then levels off.
- **On display:** light fades magenta and yellow fastest (prints go cyan), and thin dye fades proportionally faster than dense dye, so highlights and pastels go first. Light also bleaches most of the stain.
- **B&W:** washed silver is very stable; the gelatin and paper base slowly yellow.
- **Lab scans:** the negative fades in its sleeve, and the scanner's auto-balance sees it as it is now. The mid-tones come back neutral but the highlights and shadows cross over.
- The rates follow the published dark-keeping and light-fading behaviour of 1970s–90s chromogenic materials (after Wilhelm, 1993). Modern papers fade several times more slowly.
- Fading is per pixel, so it is included in exported LUTs.
</details>

<details>
<summary><b>8 · Calibration and accuracy</b></summary>

- **Measured stocks** get no colour calibration: their character comes entirely from the data.
- **Grey scale:** every stock holds a neutral grey ramp across about ±5 stops.
- **Fitted stocks** (Astia, ColorPlus, B&W) use a regularised layer-crosstalk matrix and scanner profile fitted to a ColorChecker plus each stock's documented character.
- **ColorChecker results:** mean hue difference 7–10° for the measured stocks (each film's own character, not error). Chroma is about 1.0× for Portra, 1.35× for Ektar and 1.55× for Velvia.
</details>

### Camera integration

| | Panasonic Lumix LX5 (dedicated profile) | Other cameras (≈ 940 RAW models) |
|---|---|---|
| Decoding | Apple's LX5 profile, RW2 lens-distortion correction, highlight recovery | Apple's profile for that camera, same settings |
| Noise reduction | Per-ISO table for the 1/1.63" CCD | From ISO × crop² (crop factor read from EXIF) |
| Sharpening | Off: film was never digitally sharpened | Off |
| Scene light | As-shot white balance | As-shot white balance |

## ▸ Film LUTs for Final Cut, Resolve, Photoshop and Lightroom

Every stock can be exported as a **3D LUT (`.cube`, 33³)**, using **File ▸ Export Film LUTs…** in the app or `emulsion-cli lut all out/`. A ready-made pack at default settings is attached to each [release](https://github.com/oddnebula/emulsion-98/releases/latest).

Each entry is developed through the full engine as a large uniform area: spectral exposure, measured curves, DIR couplers, optical print or lab scan, paper. Darkroom settings (push, lab, filters, paper grade, expired film…) are baked in. Input is display-referred sRGB / Rec.709 (a camera JPEG or graded video), and output is sRGB.

On the demo photo the LUT matches Emulsion 98's own render (with grain and halation off) to **0.3–0.7 levels out of 255 on average**. The rest is at sharp edges, from scatter and DIR edge effects. A LUT can't hold spatial effects, so grain, halation and edge effects stay in the app.

## ▸ Apple Photos

<p align="center">
  <img src="docs/images/photos-extension.jpg" alt="Emulsion 98 Apple Photos editing extension: develop photos on film directly inside the Photos app" width="90%">
</p>

- **Photos Library…** (⇧⌘P): browse Library, Recently Added, RAW, Favorites and albums, and import originals. The RAW file is preferred, and iCloud originals are downloaded as needed.
- **Send to Photos:** save developed photos to an "Emulsion 98" album, or **apply the film as a non-destructive edit** of the original. *Revert to Original* undoes it.
- **Photos editing extension:** in Photos, choose **Edit ▸ ⋯ ▸ Emulsion 98** to develop any photo on film without leaving Photos. Edits are re-editable, and the app and the extension share the same edit data.
  - Enable it once under **⋯ ▸ More…** in Photos, or System Settings ▸ General ▸ Login Items & Extensions ▸ Photos Editing.
  - Photos hands extensions its own rendering of the image, not the RAW file. For the RAW pipeline, import into the app and use *Apply as edit*.

## ▸ About This Darkroom

<table>
<tr>
<td width="50%"><img src="docs/images/startup.png" alt="Emulsion 98 startup screen with extensions parade, in the style of Mac OS 8"></td>
<td width="50%"><img src="docs/images/balloon-help.jpg" alt="Classic Mac Balloon Help explaining the halation control"></td>
</tr>
</table>

It's a native SwiftUI app styled after 1998's Mac OS 8 Platinum appearance. Every control, icon and sound is original, drawn or synthesised at runtime.

- **Startup screen** with the Happy Camera, an extensions parade and a startup chord.
- **WindowShade** (double-click the title bar), **Balloon Help** (⇧⌘/) and the **Control Strip**.
- **Desktop patterns**, **safelight mode**, a **wristwatch cursor**, shutter sounds and the **Darkroom Saver** screen saver.
- A **bomb dialog** and a **Sad Camera** for errors, and an About box with a secret (click the camera).
- **Get Info** (⌘I), a split before/after view (⌘\\), and keyboard navigation (⌘← ⌘→ for photos, ⌘↑ ⌘↓ for films).

## ▸ Download

Get the latest **[release](https://github.com/oddnebula/emulsion-98/releases/latest)**: unzip it and move *Emulsion 98.app* to `/Applications`.

The app is signed ad hoc, not notarised by Apple, so the first time you open it, **right-click it and choose Open**, then confirm. If macOS still refuses, run `xattr -dr com.apple.quarantine "/Applications/Emulsion 98.app"` once. To use it inside Photos, launch the app once, then enable *Emulsion 98* under **Edit ▸ ⋯ ▸ More…** in Photos.

## ▸ Installation

**System requirements:** macOS 15 Sequoia or later on Apple silicon or Intel, plus the Xcode Command Line Tools (Swift 6). Xcode itself is not needed.

```bash
git clone https://github.com/oddnebula/emulsion-98.git
cd emulsion-98
./scripts/build_app.sh
open "dist/Emulsion 98.app"
```

The build script makes the app bundle, embeds and registers the Photos extension, and signs it ad hoc for your own Mac. Move the app to `/Applications` if you want to keep it.

**Using it:**
1. Import photos with ⌘O, by dragging them in, from a camera card, or from Photos.
2. Pick a film stock and adjust it in the Darkroom panel.
3. Click the photo for the 1:1 grain loupe.
4. Press ⌘E to develop at full resolution into `~/Pictures/Emulsion 98/Developed/`. EXIF and GPS data are kept.

### Command-line tool

```bash
swift build -c release
.build/release/emulsion-cli list --long                                # stocks, halation, granularity
.build/release/emulsion-cli develop photo.RW2 portra400 out/           # full-resolution develop
.build/release/emulsion-cli develop photo.RW2 trix400 out/ --filter red25 --agitation stand
.build/release/emulsion-cli develop photo.RW2 velvia50 out/ --xpro     # cross-process; also --redscale, --scan, --push 2, --age 15 --storage fridge
.build/release/emulsion-cli develop photo.RW2 hp5 out/ --grade 4 --preflash 0.5           # multigrade paper; also --cc-y 10 --cc-m 5 --print-ev 0.2
.build/release/emulsion-cli develop photo.RW2 portra400 out/ --border fullFrame --format mf67 --surface lustre
.build/release/emulsion-cli develop photo.RW2 e100 out/ --print-age 40 --keeping album        # archival fading (album | framed)
.build/release/emulsion-cli develop photo.RW2 trix400 out/ --enlarger condenser --no-falloff   # Callier effect; even illumination
.build/release/emulsion-cli develop photo.RW2 hp5 out/ --paper-tone warm --toner sepia --toner-strength 0.3   # split tone; also --toner selenium
.build/release/emulsion-cli sheet photo.RW2 sheet.jpg                  # contact sheet of every stock
.build/release/emulsion-cli crop photo.RW2 cinestill800t c.jpg         # 1:1 crop
.build/release/emulsion-cli diag portra400                             # ColorChecker accuracy
.build/release/emulsion-cli lut all luts/                              # .cube LUTs for every stock (also --size 65)
.build/release/emulsion-cli lutcheck photo.jpg portra400               # LUT vs full develop, in 8-bit levels
.build/release/emulsion-cli granularity portra400                      # RMS granularity vs density
.build/release/emulsion-cli mtf velvia50                               # film MTF, datasheet-style
.build/release/emulsion-cli mtf portra400 --camera-blur 5.4            # sharpness budget against a camera's own blur
.build/release/emulsion-cli fade all --keeping framed                  # patch colours over 0–80 years
.build/release/emulsion-cli priors                                     # which colours the skin / foliage priors claim
```

`scripts/make_readme_images.sh` regenerates every comparison image in this README.

## ▸ Lab Notebook

These ideas were tested and dropped, so the model only keeps what measurably matters:

| Idea | Result |
|---|---|
| Biophysical skin model (melanin and haemoglobin tissue optics) | Could not reproduce pale or rosy skin chromaticity (off by about 0.02 in xy). Replaced by measured NIST skin spectra. |
| Rayleigh + Mie sky spectra for blue-sky colours | Changed film exposure by under 2 %: the smooth basis already matches skylight. Removed. |
| Foliage prior from the raw USGS population, ±2 σ window | The library's 25 near-identical marsh plots dominated, so ordinary green leaves fell outside the window. Fixed by weighting each plant group equally, finding components in a wavelength-weighted space and using a ±3–5 σ window. |
| Wider lateral spread for interlayer DIR inhibitors | Raised the overshoot of the MTF peak (Ektar from 141 % to 152 %). Reverted. |
| Boolean dye-cloud grain rendering | At RAW resolutions dye clouds are about a pixel wide, where the binned sub-emulsion statistics are equivalent. Not adopted. |

## ▸ FAQ

**How do I make digital photos look like real film on a Mac?**
Import your photos, ideally RAW files, into Emulsion 98 and choose a film stock. Instead of applying a filter, it simulates exposing, developing and printing that film from measured datasheet data, which is why highlights, skin tones, mixed light and grain behave like film.

**Is this a Kodak Portra / Fuji / Tri-X preset or LUT?**
No. There are no LUTs of finished looks. Each stock is a spectral model of the emulsion (layer sensitivities, dye spectra, characteristic curves, sub-emulsion grain) and of the paper it is printed on, so the same stock looks different in daylight, under tungsten, pushed, or overexposed.

**Does it work inside Apple Photos?**
Yes. The bundled Photos editing extension adds Emulsion 98 to **Edit ▸ ⋯** in Photos, and the app can import from and save back to your library.

**Which cameras are supported?**
Any camera Apple's RAW engine supports (about 940 models), plus JPEG, HEIC, PNG, TIFF and OpenEXR files. The Panasonic Lumix LX5 has a dedicated profile.

**Can it do cross-processing, redscale, expired film or stand development?**
Yes. Each is simulated physically from the film data, not painted on as a colour effect.

## ▸ Credits & Licence

- **Code:** MIT licence (see [`LICENSE`](LICENSE)).
- **Measured film data:** [spektrafilm](https://github.com/andreavolpato/spektrafilm) profiles by Andrea Volpato, licensed **CC BY-SA 4.0**. Copies are in `Data/spektrafilm/` with the licence and a changelog of the changes made. `Sources/FilmEngine/MeasuredData.swift` is generated from them by `scripts/convert_spektrafilm.py` and is itself CC BY-SA 4.0. Photos you develop are not affected by this licence.
- **Skin spectra:** derived from the "Reference Data Set of Human Skin Reflectance", National Institute of Standards and Technology. See C. C. Cooksey, D. W. Allen & B. K. Tsai, *J. Res. NIST* 122, 26 (2017), [doi:10.6028/jres.122.026](https://doi.org/10.6028/jres.122.026). `Sources/FilmEngine/SkinData.swift` holds only derived statistics (mean shape, principal components, chromaticity spread), generated by `scripts/convert_nist_skin.py`. NIST data is not subject to copyright in the US.
- **Foliage spectra:** derived from the USGS Spectral Library Version 7 (R. F. Kokaly et al., U.S. Geological Survey Data Series 1035, 2017, [doi:10.3133/ds1035](https://doi.org/10.3133/ds1035); data [doi:10.5066/F7RR1WDJ](https://doi.org/10.5066/F7RR1WDJ)). `Sources/FilmEngine/FoliageData.swift` holds only derived statistics, generated by `scripts/convert_usgs_foliage.py`. USGS data is in the public domain.
- **Demo photo:** beach at sunset by Nilo Velez, [WordPress.org Photos](https://wordpress.org/photos/photo/426884abe5/), **CC0** (public domain), metadata stripped. Every film rendering in this README is Emulsion 98's own output.
- **Method references:** Mallett & Yuksel 2019 (spectral primary decomposition); CIE 15 (daylight, colorimetry); ISO 3664 (viewing); the Frieser, Nutting, Siedentopf and Selwyn models of emulsion MTF and granularity.

Not affiliated with Kodak, Kodak Alaris, Fujifilm, Ilford, Harman, CineStill or Apple. Film stock names are trademarks of their owners and identify the look being emulated.

<p align="center"><sub>film simulation · film emulation · film LUT · cube LUT · Final Cut Pro LUT · DaVinci Resolve LUT · analog film look · film grain · halation · Kodak Portra · Fujifilm Velvia · Kodak Tri-X · CineStill 800T · cross-processing · redscale · expired film · RAW photo editor for Mac · Apple Photos extension · SwiftUI · color science · spectral rendering</sub></p>
