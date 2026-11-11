import SwiftUI
import AppKit
import Photos
import UniformTypeIdentifiers
import FilmEngine

/// Apple Photos integration: browse the library, import originals (RAW when present), and save
/// developed frames back — as new photos in an "Emulsion 98" album, or as a revertible edit.
enum PhotosBridge {
    static let albumTitle = "Emulsion 98"
    static let adjustmentFormat = "local.emulsion98.film"

    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    static func requestAccess() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    // MARK: Import

    /// Writes the best original of `asset` to `folder`: the RAW file if the asset has one (RAW-only or
    /// RAW+JPEG pairs), otherwise the original photo. Downloads from iCloud if needed.
    static func exportOriginal(_ asset: PHAsset, to folder: URL) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        func isRaw(_ r: PHAssetResource) -> Bool { UTType(r.uniformTypeIdentifier)?.conforms(to: .rawImage) ?? false }
        guard let res = resources.first(where: { isRaw($0) && ($0.type == .photo || $0.type == .alternatePhoto) })
            ?? resources.first(where: { $0.type == .photo })
            ?? resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first else {
            throw NSError(domain: "Emulsion98", code: 2, userInfo: [NSLocalizedDescriptionKey: "Photo has no original file"])
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var dest = folder.appendingPathComponent(res.originalFilename)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (res.originalFilename as NSString).deletingPathExtension, ext = (res.originalFilename as NSString).pathExtension
            dest = folder.appendingPathComponent("\(base)-\(n).\(ext)"); n += 1
        }
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        let target = dest
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: res, toFile: target, options: opts) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
        // Keep the capture date on the file so library sorting matches Photos.
        if let d = asset.creationDate { try? FileManager.default.setAttributes([.creationDate: d, .modificationDate: d], ofItemAtPath: dest.path) }
        return dest
    }

    // MARK: Save back

    static func album() async throws -> PHAssetCollection {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title == %@", albumTitle)
        if let a = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts).firstObject { return a }
        var id: String?
        try await PHPhotoLibrary.shared().performChanges {
            id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle).placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id, let a = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw NSError(domain: "Emulsion98", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create the \(albumTitle) album"])
        }
        return a
    }

    /// Adds a developed file as a new photo in the Emulsion 98 album (EXIF date/GPS come from the file).
    static func addToAlbum(_ file: URL, original: PHAsset?) async throws {
        let album = try await album()
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, fileURL: file, options: nil)
            if let o = original {
                req.creationDate = o.creationDate
                req.location = o.location
            }
            if let ph = req.placeholderForCreatedAsset {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([ph] as NSArray)
            }
        }
    }

    /// Applies the developed image to the original asset as a non-destructive Photos edit. The original
    /// stays in the library ("Revert to Original" in Photos undoes it); the film settings are stored as
    /// adjustment data.
    static func applyAsEdit(_ jpeg: URL, to asset: PHAsset, settings: Data) async throws {
        let opts = PHContentEditingInputRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.canHandleAdjustmentData = { $0.formatIdentifier == adjustmentFormat }
        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { c in
            asset.requestContentEditingInput(with: opts) { input, info in
                if let input { c.resume(returning: input) }
                else { c.resume(throwing: (info[PHContentEditingInputErrorKey] as? Error) ?? NSError(domain: "Emulsion98", code: 4)) }
            }
        }
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(formatIdentifier: adjustmentFormat, formatVersion: "1", data: settings)
        try FileManager.default.copyItem(at: jpeg, to: output.renderedContentURL)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).contentEditingOutput = output
        }
    }

    static func asset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    static func openPhotosApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Browser model

@MainActor
final class PhotosBrowserModel: ObservableObject {
    struct Album: Identifiable, Hashable { let id: String; let title: String; let count: Int; let collection: PHAssetCollection }

    @Published var albums: [Album] = []
    @Published var current: Album?
    @Published var assets: [PHAsset] = []
    @Published var thumbs: [String: NSImage] = [:]
    @Published var selection: Set<String> = []
    @Published var message: String = ""
    @Published var authorized = false
    @Published var rawOnly = false { didSet { reloadAssets() } }

    private let imageManager = PHCachingImageManager()
    private var requested: Set<String> = []

    func start() async {
        authorized = await PhotosBridge.requestAccess()
        guard authorized else {
            message = "Emulsion 98 needs access to your Photos library. Allow it in System Settings ▸ Privacy & Security ▸ Photos."
            return
        }
        loadAlbums()
    }

    func loadAlbums() {
        var out: [Album] = []
        func add(_ c: PHAssetCollection, _ title: String? = nil) {
            let opts = PHFetchOptions(); opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let n = PHAsset.fetchAssets(in: c, options: opts).count
            if n > 0 { out.append(Album(id: c.localIdentifier, title: title ?? c.localizedTitle ?? "Album", count: n, collection: c)) }
        }
        for (sub, title) in [(PHAssetCollectionSubtype.smartAlbumUserLibrary, "Library"), (.smartAlbumRecentlyAdded, nil),
                             (.smartAlbumRAW, "RAW"), (.smartAlbumFavorites, nil)] {
            if let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil).firstObject { add(c, title) }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
            if c.localizedTitle != PhotosBridge.albumTitle { add(c) }
        }
        albums = out
        if current == nil { current = out.first }
        reloadAssets()
    }

    func select(_ a: Album) { current = a; selection = []; reloadAssets() }

    func reloadAssets() {
        guard let c = current else { assets = []; return }
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(in: c.collection, options: opts)
        var list: [PHAsset] = []
        result.enumerateObjects { a, _, stop in
            if self.rawOnly {
                let raw = PHAssetResource.assetResources(for: a).contains { UTType($0.uniformTypeIdentifier)?.conforms(to: .rawImage) ?? false }
                if !raw { return }
            }
            list.append(a)
            if list.count >= 1500 { stop.pointee = true }
        }
        assets = list
        message = "\(list.count) photo\(list.count == 1 ? "" : "s")" + (result.count > list.count && !rawOnly ? " (showing newest \(list.count))" : "")
    }

    func thumbnail(_ a: PHAsset) {
        let id = a.localIdentifier
        guard !requested.contains(id) else { return }
        requested.insert(id)
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .fast
        imageManager.requestImage(for: a, targetSize: CGSize(width: 220, height: 220), contentMode: .aspectFill, options: opts) { [weak self] img, _ in
            guard let img else { return }
            Task { @MainActor in self?.thumbs[id] = img }
        }
    }

    func toggle(_ a: PHAsset) {
        let id = a.localIdentifier
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    var selectedAssets: [PHAsset] { assets.filter { selection.contains($0.localIdentifier) } }
}

// MARK: - Browser view (platinum window)

struct PhotosBrowser: View {
    @EnvironmentObject var lib: Library
    @StateObject private var model = PhotosBrowserModel()

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).contentShape(Rectangle())
            VStack(spacing: 0) {
                HStack {
                    Text("Photos Library").font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink)
                        .padding(.horizontal, 8).background(Plat.face)
                }
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(
                    Canvas { ctx, size in
                        for y in stride(from: 4.0, to: size.height - 4, by: 2) {
                            ctx.fill(Path(CGRect(x: 4, y: y, width: size.width - 8, height: 1)), with: .color(Plat.shade))
                            ctx.fill(Path(CGRect(x: 5, y: y + 1, width: size.width - 9, height: 1)), with: .color(Plat.light))
                        }
                    }
                )
                .overlay(Rectangle().fill(Plat.ink).frame(height: 1), alignment: .bottom)

                if model.authorized {
                    HStack(alignment: .top, spacing: 8) {
                        PlatinumGroup(title: "Albums") {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(model.albums) { a in
                                        HStack {
                                            Text(a.title).font(Plat.font(11)).foregroundStyle(Plat.ink).lineLimit(1)
                                            Spacer()
                                            Text("\(a.count)").font(Plat.font(10)).foregroundStyle(Plat.dark)
                                        }
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(model.current?.id == a.id ? Plat.highlight : Color.white)
                                        .contentShape(Rectangle())
                                        .onTapGesture { model.select(a) }
                                    }
                                }
                            }
                            .scrollIndicators(.never)
                            .sunkenWell(.white)
                        }
                        .frame(width: 200)

                        VStack(spacing: 6) {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 6)], spacing: 6) {
                                    ForEach(model.assets, id: \.localIdentifier) { a in
                                        let sel = model.selection.contains(a.localIdentifier)
                                        ZStack(alignment: .bottomTrailing) {
                                            Color.black
                                            if let t = model.thumbs[a.localIdentifier] {
                                                Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
                                            }
                                            if sel {
                                                Text("✓").font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink)
                                                    .frame(width: 18, height: 18).background(Plat.highlight)
                                                    .overlay(Rectangle().strokeBorder(Plat.ink)).padding(3)
                                            }
                                        }
                                        .frame(width: 104, height: 104).clipped()
                                        .overlay(Rectangle().strokeBorder(sel ? Plat.accent : Plat.ink, lineWidth: sel ? 3 : 1))
                                        .contentShape(Rectangle())
                                        .onTapGesture { model.toggle(a) }
                                        .onAppear { model.thumbnail(a) }
                                    }
                                }
                                .padding(6)
                            }
                            .scrollIndicators(.never)
                            .sunkenWell(Plat.photoWell)
                            HStack {
                                Toggle("RAW files only", isOn: $model.rawOnly).toggleStyle(PlatinumCheckboxStyle())
                                Text(model.message).font(Plat.font(10)).foregroundStyle(Plat.dark).lineLimit(1)
                                Spacer()
                                Button("Select All") { model.selection = Set(model.assets.map(\.localIdentifier)) }
                                    .buttonStyle(PlatinumButtonStyle())
                            }
                        }
                    }
                    .padding(10)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Text(model.message.isEmpty ? "Asking for access to Photos…" : model.message)
                            .font(Plat.font(12)).foregroundStyle(Plat.ink).multilineTextAlignment(.center).padding(.horizontal, 40)
                        Spacer()
                    }
                }

                HStack(spacing: 10) {
                    Text(model.selection.isEmpty ? "Click photos to select them." : "\(model.selection.count) selected · RAW originals are imported when present.")
                        .font(Plat.font(11)).foregroundStyle(Plat.dark)
                    Spacer()
                    Button("Cancel") { lib.showPhotosBrowser = false }
                        .buttonStyle(PlatinumButtonStyle(minWidth: 70)).keyboardShortcut(.cancelAction)
                    Button("Import \(model.selection.count)") {
                        let picked = model.selectedAssets
                        lib.showPhotosBrowser = false
                        lib.importFromPhotos(picked)
                    }
                    .buttonStyle(PlatinumButtonStyle(isDefault: true, minWidth: 80)).keyboardShortcut(.defaultAction)
                    .disabled(model.selection.isEmpty)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .frame(width: 880, height: 600)
            .background(Plat.face)
            .overlay(Bevel(raised: true).padding(1))
            .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
            .background(Rectangle().fill(Color.black.opacity(0.6)).offset(x: 3, y: 3))
        }
        .task { await model.start() }
    }
}
