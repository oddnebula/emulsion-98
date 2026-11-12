import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

public enum ExportFormat: String, CaseIterable, Codable, Identifiable {
    case jpeg, tiff16
    public var id: String { rawValue }
    public var label: String { self == .jpeg ? "JPEG (best)" : "TIFF 16-bit" }
    public var fileExtension: String { self == .jpeg ? "jpg" : "tif" }
}

public struct LoadedPhoto {
    /// Scene-linear light in linear Rec.2020 primaries.
    public var image: RGBImage
    /// Long side of the photo at full resolution (orientation applied).
    public var fullLongSide: Int
    /// True when the source was a camera-rendered JPEG/HEIC rather than RAW.
    public var isDisplayReferred: Bool
    public var capture: CaptureInfo
    /// Clipped highlights were found and rebuilt at load.
    public var highlightsRecovered = false

    public func context(fullLongSide: Int? = nil, originX: Int = 0, originY: Int = 0, seed: UInt32) -> DevelopContext {
        let long = fullLongSide ?? image.longSide
        let s = Float(long) / Float(max(image.longSide, 1))
        return DevelopContext(fullLongSide: long, originX: originX, originY: originY, seed: seed,
                              isDisplayReferred: isDisplayReferred, sceneKelvin: capture.asShotKelvin)
            .with {
                $0.exposureTime = capture.exposureTime
                $0.fullSize = SIMD2(Int((Float(image.width) * s).rounded()), Int((Float(image.height) * s).rounded()))
                // Camera JPEG / HEIC: in-camera sharpening leaves less effective blur than a raw decode.
                $0.capturePixels = self.fullLongSide
                $0.captureBlurPx = isDisplayReferred ? 0.45 : 0.55
            }
    }
}

public enum PhotoIO {
    public static let rawExtensions: Set<String> = ["rw2", "raw", "dng", "cr2", "cr3", "nef", "arw", "orf", "raf", "pef", "srw"]
    public static let imageExtensions: Set<String> = rawExtensions.union(["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif", "exr"])

    /// Wide-gamut working space so saturated camera colours reach the spectral model unclipped.
    static let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    static let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let context = CIContext(options: [.workingColorSpace: linearSpace, .cacheIntermediates: false])

    public static func isRAW(_ url: URL) -> Bool { rawExtensions.contains(url.pathExtension.lowercased()) }
    public static func isSupported(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }

    /// Stable grain seed per photo so re-exports are identical.
    public static func seed(for url: URL) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in url.lastPathComponent.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }

    /// Loads a photo as scene-linear RGB (linear sRGB primaries), optionally downscaled.
    public static func load(_ url: URL, maxLongSide: Int? = nil, recoverHighlights: Bool = true) throws -> LoadedPhoto {
        // macOS privacy protection (TCC) makes blocked files decode as black instead of failing.
        do { try FileHandle(forReadingFrom: url).close() }
        catch { throw err("macOS blocked access to \(url.lastPathComponent). Add it again with Import Photos… to grant access.") }
        var ci: CIImage
        var fullLong: Int
        let raw = isRAW(url)
        var capture = Metadata.read(url)
        capture.isRAW = raw
        if raw, let filter = CIRAWFilter(imageURL: url) {
            // As-shot white balance = the colour of the scene light the film would have seen.
            capture.asShotKelvin = filter.neutralTemperature > 1000 ? filter.neutralTemperature : nil
            capture.asShotTint = filter.neutralTint
            let profile = CameraProfile.forModel(capture.model)
            capture.profileName = profile.name
            filter.boostAmount = 0            // remove Apple's tone curve: scene-linear output
            filter.boostShadowAmount = 0
            filter.isGamutMappingEnabled = false
            if filter.isLocalToneMapSupported { filter.localToneMapAmount = 0 }
            if filter.isLensCorrectionSupported { filter.isLensCorrectionEnabled = true }
            if filter.isSharpnessSupported { filter.sharpnessAmount = profile.sharpness }
            let nr = profile.noiseReduction(iso: capture.iso, crop: capture.cropFactor)
            if filter.isLuminanceNoiseReductionSupported { filter.luminanceNoiseReductionAmount = nr.0 }
            if filter.isColorNoiseReductionSupported { filter.colorNoiseReductionAmount = nr.1 }
            if #available(macOS 26.0, *), filter.isHighlightRecoverySupported { filter.isHighlightRecoveryEnabled = true }
            filter.extendedDynamicRangeAmount = 1   // keep scene highlights above 1.0 unclipped
            let native = filter.nativeSize
            fullLong = Int(max(native.width, native.height))
            if let m = maxLongSide, fullLong > m {
                filter.scaleFactor = Float(m) / Float(fullLong)
            }
            guard let out = filter.outputImage else { throw err("Could not decode RAW file \(url.lastPathComponent)") }
            ci = out
            // nativeSize may be pre-orientation; trust the output geometry ratio.
            if maxLongSide == nil { fullLong = Int(max(ci.extent.width, ci.extent.height)) }
        } else {
            guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                throw err("Could not open \(url.lastPathComponent)")
            }
            ci = img
            fullLong = Int(max(img.extent.width, img.extent.height))
            if let m = maxLongSide, fullLong > m {
                let f = CIFilter.lanczosScaleTransform()
                f.inputImage = img
                f.scale = Float(m) / Float(fullLong)
                f.aspectRatio = 1
                ci = f.outputImage ?? img
            }
        }
        let ext = ci.extent.integral
        ci = ci.transformed(by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y))
        let w = Int(ext.width), h = Int(ext.height)
        var rgba = [Float](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { buf in
            context.render(ci, toBitmap: buf.baseAddress!, rowBytes: w * 16,
                           bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: linearSpace)
        }
        var img = RGBImage(width: w, height: h)
        for i in 0..<(w * h) {
            img.r[i] = rgba[i * 4]; img.g[i] = rgba[i * 4 + 1]; img.b[i] = rgba[i * 4 + 2]
        }
        // OpenEXR is scene-linear (renders, HDR merges): like RAW, no camera tone curve to undo.
        let sceneLinear = raw || url.pathExtension.lowercased() == "exr"
        // Where the camera clipped, rebuild the light the film would still have recorded.
        let recovered = recoverHighlights && HighlightRecovery.recover(&img)
        var p = LoadedPhoto(image: img, fullLongSide: fullLong, isDisplayReferred: !sceneLinear, capture: capture)
        p.highlightsRecovered = recovered
        return p
    }

    /// Linear Rec.2020 scene light -> sRGB-encoded image, for showing the undeveloped original.
    public static func displayOriginal(_ img: RGBImage) -> RGBImage {
        var out = img
        let m = Spectral.xyzToSRGB, toXYZ = Spectral.rec2020ToXYZ
        Developer.map3(&out.r, &out.g, &out.b) { r, g, b in
            let c = m.apply(toXYZ.apply(SIMD3(r, g, b)))
            r = Developer.encode(c.x); g = Developer.encode(c.y); b = Developer.encode(c.z)
        }
        return out
    }

    /// Fast embedded/thumbnail preview for lists.
    public static func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Converts a developed (sRGB-encoded 0…1) image into a CGImage.
    public static func cgImage(_ img: RGBImage, bits16: Bool = false) -> CGImage? {
        let w = img.width, h = img.height
        if bits16 {
            var px = [UInt16](repeating: 0, count: w * h * 4)
            for i in 0..<(w * h) {
                px[i * 4] = UInt16(min(max(img.r[i], 0), 1) * 65535 + 0.5)
                px[i * 4 + 1] = UInt16(min(max(img.g[i], 0), 1) * 65535 + 0.5)
                px[i * 4 + 2] = UInt16(min(max(img.b[i], 0), 1) * 65535 + 0.5)
                px[i * 4 + 3] = 65535
            }
            let data = px.withUnsafeBytes { Data($0) } as CFData
            guard let prov = CGDataProvider(data: data) else { return nil }
            return CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: w * 8,
                           space: srgbSpace,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                           provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            px[i * 4] = UInt8(min(max(img.r[i], 0), 1) * 255 + 0.5)
            px[i * 4 + 1] = UInt8(min(max(img.g[i], 0), 1) * 255 + 0.5)
            px[i * 4 + 2] = UInt8(min(max(img.b[i], 0), 1) * 255 + 0.5)
        }
        let data = px.withUnsafeBytes { Data($0) } as CFData
        guard let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: srgbSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Writes a developed image, carrying over the original's EXIF/GPS metadata.
    public static func save(_ img: RGBImage, to url: URL, format: ExportFormat, source: URL?, stockName: String) throws {
        guard let cg = cgImage(img, bits16: format == .tiff16) else { throw err("Could not encode image") }
        let type = (format == .jpeg ? UTType.jpeg : UTType.tiff).identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { throw err("Could not create \(url.path)") }

        var props: [CFString: Any] = [:]
        if let source, let src = CGImageSourceCreateWithURL(source as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
                if let v = p[key] { props[key] = v }
            }
            if var tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFSoftware] = "Emulsion 98"
        tiff[kCGImagePropertyTIFFImageDescription] = "Developed with \(stockName) emulation"
        props[kCGImagePropertyTIFFDictionary] = tiff
        props[kCGImagePropertyOrientation] = 1
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.95 }

        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        if !CGImageDestinationFinalize(dest) { throw err("Could not write \(url.lastPathComponent)") }
    }

    static func err(_ s: String) -> NSError {
        NSError(domain: "Emulsion98", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }
}
