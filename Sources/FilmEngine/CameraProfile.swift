import Foundation
import ImageIO

/// What the camera recorded about a frame.
public struct CaptureInfo: Equatable {
    public var make: String?
    public var model: String?
    public var lens: String?
    public var iso: Int?
    public var exposureTime: Double?
    public var fNumber: Double?
    public var focalLength: Double?
    public var focalLength35: Double?
    /// As-shot white balance (scene light) from the RAW, in kelvin.
    public var asShotKelvin: Float?
    public var asShotTint: Float?
    public var isRAW = false
    public var profileName = "Generic"

    /// Sensor crop factor relative to 35 mm, from the EXIF 35 mm-equivalent focal length.
    public var cropFactor: Double? {
        guard let f = focalLength, let f35 = focalLength35, f > 0, f35 > 0 else { return nil }
        return f35 / f
    }

    public var cameraName: String {
        let mk = (make ?? "").trimmingCharacters(in: .whitespaces)
        let md = (model ?? "").trimmingCharacters(in: .whitespaces)
        if md.isEmpty { return mk.isEmpty ? "Unknown camera" : mk }
        return md.lowercased().hasPrefix(mk.lowercased().split(separator: " ").first.map(String.init) ?? "~") ? md : "\(mk) \(md)"
    }

    public var exposureSummary: String {
        var parts: [String] = []
        if let iso { parts.append("ISO \(iso)") }
        if let t = exposureTime { parts.append(t >= 0.5 ? String(format: "%.1fs", t) : "1/\(Int((1 / t).rounded()))s") }
        if let f = fNumber { parts.append(String(format: "f/%.1f", f)) }
        if let fl = focalLength {
            parts.append(focalLength35.map { String(format: "%.1fmm (%.0fmm eq.)", fl, $0) } ?? String(format: "%.1fmm", fl))
        }
        return parts.joined(separator: " · ")
    }
}

/// Per-camera decoding choices. Film grain should replace digital noise, not sit on top of it, and film
/// never had digital sharpening, so the RAW decoder is tuned per camera and ISO.
public struct CameraProfile {
    public let name: String
    let matches: (String) -> Bool
    /// (ISO) -> (luminance NR, colour NR) for Apple's RAW decoder, 0…1.
    let noiseReduction: (Int, Double) -> (Float, Float)
    let sharpness: Float
    /// Typical crop factor, used when EXIF lacks the 35 mm-equivalent focal length.
    let defaultCrop: Double

    /// Panasonic Lumix DMC-LX5: 10 MP 1/1.63" CCD (crop ≈ 4.7), base ISO 80. Clean to ISO 200,
    /// coloured blotchy chroma noise from ISO 400 — colour NR does most of the work so luminance
    /// detail survives for the grain to sit on. Its RW2 files carry lens-distortion data, which Apple
    /// applies, and highlight recovery reclaims about a stop the CCD's JPEGs throw away.
    public static let lx5 = CameraProfile(
        name: "Panasonic LX5",
        matches: { $0.contains("LX5") },
        noiseReduction: { iso, _ in
            switch iso {
            case ..<125: return (0.05, 0.30)
            case ..<250: return (0.12, 0.45)
            case ..<500: return (0.25, 0.65)
            case ..<1000: return (0.40, 0.80)
            case ..<2000: return (0.55, 0.92)
            default: return (0.68, 1.0)
            }
        },
        sharpness: 0, defaultCrop: 4.67)

    /// Other cameras: noise scales with ISO × crop² (equivalent-light), normalised to the LX5.
    public static let generic = CameraProfile(
        name: "Generic",
        matches: { _ in true },
        noiseReduction: { iso, crop in
            let index = Double(iso) * crop * crop / 100      // LX5 at ISO 80 ≈ 17
            let stops = log2(max(index, 1) / 17)
            return (Float(min(max(0.05 + 0.12 * stops, 0), 0.7)), Float(min(max(0.3 + 0.13 * stops, 0.2), 1)))
        },
        sharpness: 0, defaultCrop: 1.5)

    static let all = [lx5]

    public static func forModel(_ model: String?) -> CameraProfile {
        guard let m = model else { return generic }
        return all.first { $0.matches(m) } ?? generic
    }

    public func noiseReduction(iso: Int?, crop: Double?) -> (Float, Float) {
        noiseReduction(iso ?? 100, crop ?? defaultCrop)
    }
}

enum Metadata {
    static func read(_ url: URL) -> CaptureInfo {
        var c = CaptureInfo()
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return c }
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let aux = p[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        c.make = tiff[kCGImagePropertyTIFFMake] as? String
        c.model = tiff[kCGImagePropertyTIFFModel] as? String
        c.lens = (exif[kCGImagePropertyExifLensModel] as? String) ?? (aux[kCGImagePropertyExifAuxLensModel] as? String)
        c.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        c.exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        c.fNumber = exif[kCGImagePropertyExifFNumber] as? Double
        c.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        c.focalLength35 = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double) ?? (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int).map(Double.init)
        c.profileName = CameraProfile.forModel(c.model).name
        return c
    }
}
