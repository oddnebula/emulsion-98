import SwiftUI
import AppKit
import FilmEngine
import Photos

/// Owns decoded buffers and does all heavy image work off the main thread.
actor RenderService {
    private var previewCache: (URL, LoadedPhoto)?
    private var fullCache: (URL, LoadedPhoto)?
    static let previewLong = 1600

    private func previewPhoto(_ url: URL) throws -> LoadedPhoto {
        if let c = previewCache, c.0 == url { return c.1 }
        let p = try PhotoIO.load(url, maxLongSide: Self.previewLong)
        previewCache = (url, p)
        return p
    }

    private func fullPhoto(_ url: URL) throws -> LoadedPhoto {
        if let c = fullCache, c.0 == url { return c.1 }
        fullCache = nil
        let p = try PhotoIO.load(url)
        fullCache = (url, p)
        return p
    }

    func preview(_ url: URL, stock: FilmStock, settings: DevelopSettings) throws -> (developed: CGImage?, original: CGImage?, capture: CaptureInfo) {
        let p = try previewPhoto(url)
        let dev = Developer.develop(p.image, stock: stock, settings: settings, context: p.context(seed: PhotoIO.seed(for: url)))
        return (PhotoIO.cgImage(dev), PhotoIO.cgImage(PhotoIO.displayOriginal(p.image)), p.capture)
    }

    func stockThumbs(_ url: URL, stocks: [FilmStock], settings: DevelopSettings) throws -> [String: CGImage] {
        let p = try previewPhoto(url)
        let small = p.image.downscaled(toLongSide: 180)
        var out: [String: CGImage] = [:]
        for s in stocks {
            let ctx = p.context(fullLongSide: small.longSide, seed: PhotoIO.seed(for: url))
            if let cg = PhotoIO.cgImage(Developer.develop(small, stock: s, settings: settings, context: ctx)) { out[s.id] = cg }
        }
        return out
    }

    /// 1:1 crop at full resolution so grain can be judged exactly as exported.
    func loupe(_ url: URL, stock: FilmStock, settings: DevelopSettings, point: CGPoint, size: Int) throws -> CGImage? {
        let p = try fullPhoto(url)
        let img = p.image
        let margin = 64
        let x = Int(CGFloat(img.width) * point.x) - size / 2, y = Int(CGFloat(img.height) * point.y) - size / 2
        let cx = max(0, min(img.width - size, x)), cy = max(0, min(img.height - size, y))
        let ex = max(0, cx - margin), ey = max(0, cy - margin)
        let crop = img.cropped(x: ex, y: ey, width: size + 2 * margin, height: size + 2 * margin)
        let ctx = p.context(originX: ex, originY: ey, seed: PhotoIO.seed(for: url))
        let dev = Developer.develop(crop, stock: stock, settings: settings, context: ctx)
        let inner = dev.cropped(x: cx - ex, y: cy - ey, width: size, height: size)
        return PhotoIO.cgImage(inner)
    }

    func export(_ url: URL, stock: FilmStock, settings: DevelopSettings, to dest: URL, format: ExportFormat) throws {
        let p = try PhotoIO.load(url)
        let ctx = p.context(seed: PhotoIO.seed(for: url))
        let dev = Developer.develop(p.image, stock: stock, settings: settings, context: ctx)
        try PhotoIO.save(dev, to: dest, format: format, source: url, stockName: stock.displayName)
    }
}

enum ExportDestination: String, CaseIterable {
    case folder, photos, both
    var label: String {
        switch self { case .folder: "Folder only"; case .photos: "Photos only"; case .both: "Folder + Photos" }
    }
    var usesPhotos: Bool { self != .folder }
    var usesFolder: Bool { self != .photos }
}

struct Photo: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isRAW: Bool { PhotoIO.isRAW(url) }
}

struct RetroDialog: Identifiable {
    enum Icon { case note, caution, film, bomb }
    let id = UUID()
    var icon: Icon = .note
    var title: String
    var message: String
    var buttons: [(String, () -> Void)]
    var defaultIndex: Int = 0
}

@MainActor
final class Library: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var selection: URL? { didSet { if oldValue != selection { photoChanged() } } }
    @Published var stockID: String { didSet { UserDefaults.standard.set(stockID, forKey: "stock"); scheduleRender(); loupeDirty() } }
    @Published var settings: DevelopSettings { didSet { saveSettings(); scheduleRender(); scheduleThumbs(); loupeDirty() } }
    @Published var exportFormat: ExportFormat { didSet { UserDefaults.standard.set(exportFormat.rawValue, forKey: "exportFormat") } }
    @Published var kindFilter: FilmKind?
    @Published var watchCards: Bool { didSet { UserDefaults.standard.set(watchCards, forKey: "watchCards") } }

    @Published var preview: NSImage?
    @Published var capture: CaptureInfo?
    @Published var original: NSImage?
    @Published var showOriginal = false
    @Published var stockThumbs: [String: NSImage] = [:]
    @Published var photoThumbs: [URL: NSImage] = [:]
    @Published var loupe: NSImage?
    @Published var loupePoint: CGPoint? = nil
    @Published var rendering = false

    @Published var status = "Ready."
    @Published var progress: Double?
    @Published var busy = false { didSet { busy ? WatchCursor.start() : WatchCursor.stop() } }
    @Published var renderError: String?
    static let split = SplitState()

    // MARK: Navigation
    func step(photo d: Int) {
        guard !photos.isEmpty else { return }
        let i = photos.firstIndex { $0.url == selection } ?? 0
        selection = photos[min(max(i + d, 0), photos.count - 1)].url
    }
    func step(stock d: Int) {
        let list = visibleStocks
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == stockID } ?? 0
        stockID = list[(i + d + list.count) % list.count].id
    }
    @Published var dialog: RetroDialog?
    @Published var showPhotosBrowser = false
    @Published var destination: ExportDestination { didSet { UserDefaults.standard.set(destination.rawValue, forKey: "destination") } }
    /// For photos imported from Photos: apply the film as a revertible edit of the original asset.
    @Published var editInPlace: Bool { didSet { UserDefaults.standard.set(editInPlace, forKey: "editInPlace") } }
    /// Library file path -> Photos asset local identifier, for photos imported from Photos.
    private(set) var photoLinks: [String: String] = [:]

    let renderer = RenderService()
    private var renderTask: Task<Void, Never>?
    private var thumbTask: Task<Void, Never>?
    private var loupeTask: Task<Void, Never>?
    private var mountObserver: NSObjectProtocol?

    var stock: FilmStock { FilmStock.stock(id: stockID) ?? FilmStock.catalog[1] }
    var visibleStocks: [FilmStock] { FilmStock.catalog.filter { kindFilter == nil || $0.kind == kindFilter } }

    static let rootFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Emulsion 98")
    static var originalsFolder: URL { rootFolder.appendingPathComponent("Originals") }
    static var developedFolder: URL { rootFolder.appendingPathComponent("Developed") }
    private static var libraryFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Emulsion98")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    init() {
        let d = UserDefaults.standard
        stockID = d.string(forKey: "stock") ?? "portra400"
        exportFormat = ExportFormat(rawValue: d.string(forKey: "exportFormat") ?? "") ?? .jpeg
        destination = ExportDestination(rawValue: d.string(forKey: "destination") ?? "") ?? .folder
        editInPlace = d.object(forKey: "editInPlace") as? Bool ?? false
        if let data = try? Data(contentsOf: Self.linksFile), let m = try? JSONDecoder().decode([String: String].self, from: data) { photoLinks = m }
        watchCards = d.object(forKey: "watchCards") as? Bool ?? true
        if let data = d.data(forKey: "settings"), let s = try? JSONDecoder().decode(DevelopSettings.self, from: data) { settings = s }
        else { settings = DevelopSettings() }
        loadLibrary()
        startWatchingCards()
        if selection == nil { selection = photos.first?.url }
        if photos.isEmpty { status = "Drop photos here, choose File ▸ Import Photos…, or insert your camera card." }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
    }

    // MARK: Library persistence

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: Self.libraryFile),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        photos = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }.map { Photo(url: $0) }
        loadPhotoThumbs(photos)
    }

    private static var linksFile: URL { libraryFile.deletingLastPathComponent().appendingPathComponent("photos-links.json") }
    func isFromPhotos(_ url: URL) -> Bool { photoLinks[url.path] != nil }

    // MARK: Apple Photos

    func importFromPhotos(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let folder = Self.originalsFolder.appendingPathComponent("From Photos")
        busy = true; progress = 0
        Task {
            var added: [URL] = []
            for (i, a) in assets.enumerated() {
                status = "Fetching original \(i + 1) of \(assets.count) from Photos…"
                if let url = try? await PhotosBridge.exportOriginal(a, to: folder) {
                    added.append(url)
                    photoLinks[url.path] = a.localIdentifier
                }
                progress = Double(i + 1) / Double(assets.count)
            }
            if let data = try? JSONEncoder().encode(photoLinks) { try? data.write(to: Self.linksFile) }
            busy = false; progress = nil
            add(added)
            let raws = added.filter { PhotoIO.isRAW($0) }.count
            status = "Imported \(added.count) from Photos (\(raws) RAW)."
            if added.count < assets.count {
                dialog = RetroDialog(icon: .caution, title: "Some photos were skipped",
                                     message: "\(assets.count - added.count) of \(assets.count) originals could not be fetched (they may still be downloading from iCloud).",
                                     buttons: [("OK", {})])
            }
        }
    }

    private func saveLibrary() {
        let paths = photos.map { $0.url.path }
        if let data = try? JSONEncoder().encode(paths) { try? data.write(to: Self.libraryFile) }
    }

    func add(_ urls: [URL]) {
        var found: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                found += Self.images(in: u)
            } else if PhotoIO.isSupported(u) { found.append(u) }
        }
        let existing = Set(photos.map(\.url))
        let new = found.filter { !existing.contains($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { Photo(url: $0) }
        guard !new.isEmpty else { status = "No new photos found."; return }
        photos += new
        saveLibrary()
        loadPhotoThumbs(new)
        selection = new.first?.url
        status = "Added \(new.count) photo\(new.count == 1 ? "" : "s")."
    }

    func removeSelected() {
        guard let sel = selection, let i = photos.firstIndex(where: { $0.url == sel }) else { return }
        photos.remove(at: i)
        saveLibrary()
        selection = photos.isEmpty ? nil : photos[min(i, photos.count - 1)].url
        if photos.isEmpty { preview = nil; original = nil; loupe = nil }
    }

    static func images(in folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e where PhotoIO.isSupported(u) { out.append(u) }
        // Prefer RAW when a camera wrote RAW+JPEG pairs.
        let raws = Set(out.filter { PhotoIO.isRAW($0) }.map { $0.deletingPathExtension().path })
        return out.filter { PhotoIO.isRAW($0) || !raws.contains($0.deletingPathExtension().path) }
    }

    private func loadPhotoThumbs(_ list: [Photo]) {
        for p in list {
            let url = p.url
            Task.detached(priority: .utility) {
                if let cg = PhotoIO.thumbnail(url, maxPixel: 200) {
                    let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    await MainActor.run { self.photoThumbs[url] = img }
                }
            }
        }
    }

    func openPanel() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.message = "Choose photos or folders to add to Emulsion 98"
        if p.runModal() == .OK { add(p.urls) }
    }

    // MARK: Rendering

    private func photoChanged() {
        preview = nil; original = nil; loupe = nil; loupePoint = nil; stockThumbs = [:]; capture = nil
        scheduleRender(delay: 0)
        scheduleThumbs(delay: 0.05)
    }

    func scheduleRender(delay: Double = 0.03) {
        renderTask?.cancel()
        guard let url = selection else { return }
        let stock = self.stock, settings = self.settings
        renderTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            if Task.isCancelled { return }
            rendering = true
            do {
                let r = try await renderer.preview(url, stock: stock, settings: settings)
                if Task.isCancelled { return }
                if let d = r.developed { preview = NSImage(cgImage: d, size: NSSize(width: d.width, height: d.height)) }
                if let o = r.original { original = NSImage(cgImage: o, size: NSSize(width: o.width, height: o.height)) }
                capture = r.capture
                renderError = nil
            } catch {
                status = error.localizedDescription
                if !Task.isCancelled { renderError = error.localizedDescription; Retro.shared.play(.error) }
            }
            rendering = false
        }
    }

    func scheduleThumbs(delay: Double = 0.35) {
        thumbTask?.cancel()
        guard let url = selection else { return }
        let settings = self.settings
        thumbTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            if Task.isCancelled { return }
            guard let t = try? await renderer.stockThumbs(url, stocks: FilmStock.catalog, settings: settings) else { return }
            if Task.isCancelled { return }
            stockThumbs = t.mapValues { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
    }

    func inspect(at point: CGPoint) {
        loupePoint = point
        loupeDirty(delay: 0)
    }

    private func loupeDirty(delay: Double = 0.25) {
        loupeTask?.cancel()
        guard let url = selection, let pt = loupePoint else { return }
        let stock = self.stock, settings = self.settings
        loupeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            if Task.isCancelled { return }
            if let cg = try? await renderer.loupe(url, stock: stock, settings: settings, point: pt, size: 240), !Task.isCancelled {
                loupe = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }

    // MARK: Export

    func develop(all: Bool) {
        let list = all ? photos : photos.filter { $0.url == selection }
        guard !list.isEmpty, !busy else { return }
        let stock = self.stock, settings = self.settings, format = self.exportFormat
        let dest = self.destination, inPlace = self.editInPlace, links = self.photoLinks
        let day = Self.dayString()
        let folder = dest.usesFolder
            ? Self.developedFolder.appendingPathComponent(day).appendingPathComponent(stock.displayName)
            : FileManager.default.temporaryDirectory.appendingPathComponent("Emulsion98-\(UUID().uuidString)")
        busy = true; progress = 0
        Retro.shared.play(.shutter)
        Task {
            var done = 0, failed = 0, toPhotos = 0, edits = 0
            var photosOK = true
            if dest.usesPhotos { photosOK = await PhotosBridge.requestAccess() }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let adjustment = (try? JSONEncoder().encode(["stock": stock.id, "exposure": "\(settings.exposure)", "push": "\(settings.push)",
                                                        "grain": "\(settings.grain)", "halation": "\(settings.halation)",
                                                        "format": settings.format.rawValue, "lab": "\(settings.labCorrection)",
                                                        "process": settings.lab.rawValue, "sceneLight": "\(settings.sceneLight)",
                                                        "agitation": settings.agitation.rawValue, "ageYears": "\(settings.ageYears)",
                                                        "storage": settings.storage.rawValue, "filter": settings.filter.rawValue,
                                                        "crossProcess": "\(settings.crossProcess)", "redscale": "\(settings.redscale)"])) ?? Data()
            for p in list {
                status = "Developing \(p.name) in \(stock.displayName)… (\(done + 1) of \(list.count))"
                let base = p.url.deletingPathExtension().lastPathComponent
                let file = folder.appendingPathComponent("\(base)_\(stock.id).\(format.fileExtension)")
                do {
                    try await renderer.export(p.url, stock: stock, settings: settings, to: file, format: format)
                    if dest.usesPhotos && photosOK {
                        let original = links[p.url.path].flatMap { PhotosBridge.asset(id: $0) }
                        if inPlace, let original {
                            // Photos edits must be JPEG.
                            var jpeg = file
                            if format != .jpeg {
                                jpeg = folder.appendingPathComponent("\(base)_\(stock.id)_edit.jpg")
                                try await renderer.export(p.url, stock: stock, settings: settings, to: jpeg, format: .jpeg)
                            }
                            try await PhotosBridge.applyAsEdit(jpeg, to: original, settings: adjustment)
                            edits += 1
                        } else {
                            try await PhotosBridge.addToAlbum(file, original: original)
                            toPhotos += 1
                        }
                    }
                } catch { failed += 1 }
                done += 1
                progress = Double(done) / Double(list.count)
            }
            if !dest.usesFolder { try? FileManager.default.removeItem(at: folder) }
            busy = false; progress = nil
            status = "Developed \(done - failed) photo\(done - failed == 1 ? "" : "s") in \(stock.displayName)."
            if failed > 0 { Retro.shared.play(.error) } else { Retro.shared.play(.done) }
            var msg = "\(done - failed) of \(list.count) photo\(list.count == 1 ? " was" : "s were") developed in \(stock.displayName)."
            if toPhotos > 0 { msg += " \(toPhotos) added to the “\(PhotosBridge.albumTitle)” album in Photos." }
            if edits > 0 { msg += " \(edits) applied as edits to the originals in Photos (Revert to Original undoes them)." }
            if dest.usesPhotos && !photosOK { msg += " Photos access was not granted, so nothing was sent to Photos." }
            if failed > 0 { msg += " \(failed) failed." }
            var buttons: [(String, () -> Void)] = []
            if dest.usesPhotos && photosOK { buttons.append(("Open Photos", { PhotosBridge.openPhotosApp() })) }
            if dest.usesFolder { buttons.append(("Show in Finder", { NSWorkspace.shared.activateFileViewerSelecting([folder]) })) }
            buttons.append(("OK", {}))
            if failed > 0 && failed == list.count {
                dialog = RetroDialog(icon: .bomb, title: "Sorry, a darkroom error occurred.",
                                     message: "Error type 11 (light leak): none of the \(list.count) photo\(list.count == 1 ? "" : "s") could be developed. The originals are untouched. Check that the files still exist and that Emulsion 98 may read them.",
                                     buttons: [("Restart", { [weak self] in self?.scheduleRender() }), ("Resume", {})], defaultIndex: 1)
            } else {
                dialog = RetroDialog(icon: .film, title: "Development complete", message: msg, buttons: buttons, defaultIndex: buttons.count - 1)
            }
        }
    }

    static func dayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    // MARK: Camera cards

    private func startWatchingCards() {
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let vol = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor in
                guard let self, self.watchCards else { return }
                self.offerCardImport(vol)
            }
        }
    }

    func importFromCard() {
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let cards = vols.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("DCIM").path) }
        if let c = cards.first { offerCardImport(c, explicit: true) }
        else {
            dialog = RetroDialog(icon: .caution, title: "No camera card found",
                                 message: "Insert your camera's SD card (it should contain a DCIM folder), then try again.",
                                 buttons: [("OK", {})])
        }
    }

    private func offerCardImport(_ volume: URL, explicit: Bool = false) {
        let dcim = volume.appendingPathComponent("DCIM")
        guard FileManager.default.fileExists(atPath: dcim.path) else { return }
        let all = Self.images(in: dcim)
        let fresh = all.filter { !Self.alreadyImported($0) }
        let name = volume.lastPathComponent
        if fresh.isEmpty {
            if explicit { dialog = RetroDialog(icon: .note, title: "Nothing new", message: "Every photo on “\(name)” has already been imported.", buttons: [("OK", {})]) }
            return
        }
        NSSound(named: "Tink")?.play()
        dialog = RetroDialog(icon: .film, title: "Camera card inserted",
                             message: "The card “\(name)” has \(fresh.count) new photo\(fresh.count == 1 ? "" : "s"). Copy \(fresh.count == 1 ? "it" : "them") into Emulsion 98?",
                             buttons: [("Not Now", {}), ("Import", { [weak self] in self?.copyFromCard(fresh) })],
                             defaultIndex: 1)
    }

    private static func alreadyImported(_ url: URL) -> Bool {
        guard let e = FileManager.default.enumerator(at: originalsFolder, includingPropertiesForKeys: nil) else { return false }
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        for case let u as URL in e where u.lastPathComponent == name {
            if (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) == size { return true }
        }
        return false
    }

    private func copyFromCard(_ files: [URL]) {
        let dest = Self.originalsFolder.appendingPathComponent(Self.dayString())
        busy = true; progress = 0
        Task {
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            var copied: [URL] = []
            for (i, f) in files.enumerated() {
                status = "Copying \(f.lastPathComponent)… (\(i + 1) of \(files.count))"
                var target = dest.appendingPathComponent(f.lastPathComponent)
                var n = 2
                while FileManager.default.fileExists(atPath: target.path) {
                    target = dest.appendingPathComponent("\(f.deletingPathExtension().lastPathComponent)-\(n).\(f.pathExtension)"); n += 1
                }
                let src = f, dst = target
                let ok = await Task.detached { (try? FileManager.default.copyItem(at: src, to: dst)) != nil }.value
                if ok { copied.append(target) }
                progress = Double(i + 1) / Double(files.count)
            }
            busy = false; progress = nil
            add(copied)
            status = "Imported \(copied.count) photo\(copied.count == 1 ? "" : "s") from the card."
        }
    }

    func showAbout() { Retro.shared.showAbout = true }

    /// Special ▸ Clean Up: arrange the filmstrip by name.
    func cleanUp() {
        photos.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        saveLibrary()
        Retro.shared.play(.click)
        status = "Cleaned up \(photos.count) photo\(photos.count == 1 ? "" : "s")."
    }
}
