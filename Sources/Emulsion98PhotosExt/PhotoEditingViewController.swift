import Cocoa
import SwiftUI
import Photos
import PhotosUI
import FilmEngine

/// "Emulsion 98" in Photos ▸ Edit ▸ Extensions: develop any photo in the library on film, in place,
/// as a non-destructive, re-editable Photos edit (Revert to Original undoes it).
@objc(PhotoEditingViewController)
final class PhotoEditingViewController: NSViewController, PHContentEditingController {
    let model = ExtModel()
    private var input: PHContentEditingInput?

    override func loadView() {
        let host = NSHostingView(rootView: ExtRoot().environmentObject(model))
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 720)
        view = host
    }

    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        adjustmentData.formatIdentifier == ExtModel.format
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: NSImage) {
        input = contentEditingInput
        model.start(contentEditingInput, placeholder: placeholderImage)
    }

    func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        guard let input else { completionHandler(nil); return }
        model.finish(input, completion: completionHandler)
    }

    var shouldShowCancelConfirmation: Bool { false }
    func cancelContentEditing() {}
}

/// State of one editing session.
final class ExtModel: ObservableObject {
    static let format = "local.emulsion98.film"

    @Published var stockID = UserDefaults.standard.string(forKey: "stock") ?? "portra400" { didSet { schedule() } }
    @Published var settings = DevelopSettings() { didSet { schedule() } }
    @Published var preview: NSImage?
    @Published var original: NSImage?
    @Published var status = "Loading photo…"
    @Published var busy = false
    @Published var kindFilter: FilmKind?

    private var photo: LoadedPhoto?
    private var url: URL?
    private var generation = 0
    private let queue = DispatchQueue(label: "emulsion98.ext.render", qos: .userInitiated)

    var stock: FilmStock { FilmStock.stock(id: stockID) ?? FilmStock.catalog[0] }
    var visibleStocks: [FilmStock] { FilmStock.catalog.filter { kindFilter == nil || $0.kind == kindFilter } }

    func start(_ input: PHContentEditingInput, placeholder: NSImage) {
        preview = placeholder
        // Re-opening our own edit: Photos hands back the original plus our stored settings.
        if let adj = input.adjustmentData, adj.formatIdentifier == Self.format { restore(adj.data) }
        guard let url = input.fullSizeImageURL else { status = "Photos did not provide an image."; return }
        load(url)
    }

    func load(_ url: URL) {
        self.url = url
        queue.async { [weak self] in
            do {
                let p = try PhotoIO.load(url, maxLongSide: 1400)
                let orig = PhotoIO.cgImage(PhotoIO.displayOriginal(p.image)).map { NSImage(cgImage: $0, size: .zero) }
                DispatchQueue.main.async {
                    self?.photo = p; self?.original = orig
                    self?.status = p.capture.cameraName == "Unknown camera" ? "Ready." : "\(p.capture.cameraName) · \(p.capture.exposureSummary)"
                    self?.schedule(delay: 0)
                }
            } catch {
                DispatchQueue.main.async { self?.status = error.localizedDescription }
            }
        }
    }

    func schedule(delay: Double = 0.05) {
        guard let photo, let url else { return }
        generation += 1
        let gen = generation, stock = self.stock, settings = self.settings
        busy = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation else { return }
            let ctx = photo.context(seed: PhotoIO.seed(for: url))
            let out = Developer.develop(photo.image, stock: stock, settings: settings, context: ctx)
            let img = PhotoIO.cgImage(out).map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.preview = img; self.busy = false
            }
        }
    }

    func finish(_ input: PHContentEditingInput, completion: @escaping (PHContentEditingOutput?) -> Void) {
        guard let url = input.fullSizeImageURL else { completion(nil); return }
        let stock = self.stock, settings = self.settings
        UserDefaults.standard.set(stock.id, forKey: "stock")
        status = "Developing at full resolution…"; busy = true
        let data = adjustmentData(stock: stock, settings: settings)
        queue.async {
            do {
                let p = try PhotoIO.load(url)
                let dev = Developer.develop(p.image, stock: stock, settings: settings, context: p.context(seed: PhotoIO.seed(for: url)))
                let output = PHContentEditingOutput(contentEditingInput: input)
                try PhotoIO.save(dev, to: output.renderedContentURL, format: .jpeg, source: url, stockName: stock.displayName)
                output.adjustmentData = PHAdjustmentData(formatIdentifier: Self.format, formatVersion: "1", data: data)
                completion(output)
            } catch {
                completion(nil)
            }
        }
    }

    // Same keys the Emulsion 98 app writes, so edits made in either place re-open in the other.
    func adjustmentData(stock: FilmStock, settings s: DevelopSettings) -> Data {
        (try? JSONEncoder().encode(["stock": stock.id, "exposure": "\(s.exposure)", "push": "\(s.push)", "grain": "\(s.grain)",
                                    "halation": "\(s.halation)", "format": s.format.rawValue, "lab": "\(s.labCorrection)",
                                    "process": s.lab.rawValue, "sceneLight": "\(s.sceneLight)",
                                    "agitation": s.agitation.rawValue, "ageYears": "\(s.ageYears)", "storage": s.storage.rawValue,
                                    "filter": s.filter.rawValue, "crossProcess": "\(s.crossProcess)", "redscale": "\(s.redscale)",
                                    "ccYellow": "\(s.ccYellow)", "ccMagenta": "\(s.ccMagenta)", "printExposure": "\(s.printExposure)",
                                    "preflash": "\(s.preflash)", "paperGrade": "\(s.paperGrade)", "paperSurface": s.paperSurface.rawValue,
                                    "printAge": "\(s.printAge)", "keeping": s.keeping.rawValue])) ?? Data()
    }

    func restore(_ data: Data) {
        guard let d = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        var s = DevelopSettings()
        if let v = d["exposure"].flatMap(Float.init) { s.exposure = v }
        if let v = d["push"].flatMap(Float.init) { s.push = v }
        if let v = d["grain"].flatMap(Float.init) { s.grain = v }
        if let v = d["halation"].flatMap(Float.init) { s.halation = v }
        if let v = d["format"].flatMap(FilmFormat.init(rawValue:)) { s.format = v }
        if let v = d["lab"].flatMap(Float.init) { s.labCorrection = v }
        if let v = d["process"].flatMap(LabProcess.init(rawValue:)) { s.lab = v }
        if let v = d["sceneLight"] { s.sceneLight = v == "true" }
        if let v = d["agitation"].flatMap(Agitation.init(rawValue:)) { s.agitation = v }
        if let v = d["ageYears"].flatMap(Float.init) { s.ageYears = v }
        if let v = d["storage"].flatMap(Storage.init(rawValue:)) { s.storage = v }
        if let v = d["filter"].flatMap(LensFilter.init(rawValue:)) { s.filter = v }
        if let v = d["crossProcess"] { s.crossProcess = v == "true" }
        if let v = d["redscale"] { s.redscale = v == "true" }
        if let v = d["ccYellow"].flatMap(Float.init) { s.ccYellow = v }
        if let v = d["ccMagenta"].flatMap(Float.init) { s.ccMagenta = v }
        if let v = d["printExposure"].flatMap(Float.init) { s.printExposure = v }
        if let v = d["preflash"].flatMap(Float.init) { s.preflash = v }
        if let v = d["paperGrade"].flatMap(Float.init) { s.paperGrade = v }
        if let v = d["paperSurface"].flatMap(PaperSurface.init(rawValue:)) { s.paperSurface = v }
        if let v = d["printAge"].flatMap(Float.init) { s.printAge = v }
        if let v = d["keeping"].flatMap(Keeping.init(rawValue:)) { s.keeping = v }
        settings = s
        if let id = d["stock"], FilmStock.stock(id: id) != nil { stockID = id }
    }
}
