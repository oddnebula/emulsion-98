import SwiftUI
import AppKit
import FilmEngine

/// Developer aid: `Emulsion\ 98 --snapshot <dir>` renders key views to PNG (for checking the UI headlessly).
@MainActor
enum Snapshot {
    static var active = false

    static func runIfRequested(library: Library) -> Bool {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--readme"), i + 2 < a.count {
            readme(library: library, out: URL(fileURLWithPath: a[i + 1]), photo: URL(fileURLWithPath: a[i + 2]))
            return true
        }
        guard let i = a.firstIndex(of: "--snapshot"), i + 1 < a.count else { return false }
        active = true
        let dir = URL(fileURLWithPath: a[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let retro = Retro.shared
        func save<V: View>(_ name: String, _ w: CGFloat, _ h: CGFloat, _ v: V) {
            let r = ImageRenderer(content: v.environmentObject(library).frame(width: w, height: h).environment(\.colorScheme, .light))
            r.scale = 1
            guard let cg = r.cgImage else { print("failed \(name)"); return }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + ".png"))
        }
        // Snapshots must not change the user's preferences: remember and restore them.
        let saved = (retro.sounds, retro.stripOpen, retro.pattern, retro.showStartup, library.settings)
        defer {
            retro.sounds = saved.0; retro.stripOpen = saved.1; retro.pattern = saved.2; retro.showStartup = saved.3
            library.settings = saved.4
            UserDefaults.standard.synchronize()   // the process exits right after: flush the restore
        }
        retro.sounds = false
        retro.starting = false; retro.stripOpen = true
        save("main", 1320, 860, MainView())
        retro.balloons = true
        retro.tip = BalloonTip(text: "Develop All. Develops every photo on the filmstrip. Go make a coffee; the darkroom will chime when it's done.", rect: CGRect(x: 1180, y: 30, width: 110, height: 24))
        save("balloon", 1320, 860, MainView())
        retro.balloons = false
        retro.showAbout = true
        save("about", 1320, 860, MainView())
        retro.showAbout = false
        retro.safelight = true
        save("safelight", 1320, 860, MainView())
        retro.safelight = false
        retro.pattern = .bondi
        save("startup", 900, 600, StartupScreenStatic())
        retro.pattern = .darkroom
        library.dialog = RetroDialog(icon: .bomb, title: "Sorry, a darkroom error occurred.", message: "Error type 11 (light leak): none of the 3 photos could be developed.", buttons: [("Restart", {}), ("Resume", {})], defaultIndex: 1)
        save("bomb", 1320, 860, MainView())
        library.dialog = nil
        save("sad", 500, 300, ZStack { PatternFill(pattern: .platinum); SadCameraView(message: "The file “IMG_0042.RW2” could not be opened.") })
        retro.saverOn = true
        save("saver", 900, 560, DarkroomSaver())
        retro.saverOn = false
        let sp = SplitState(); sp.on = true; sp.pos = 0.42
        let imgs = a.firstIndex(of: "--split-images").map { (NSImage(contentsOfFile: a[$0 + 1]), NSImage(contentsOfFile: a[$0 + 2])) }
        if let (orig, film) = imgs, let orig, let film {
            let sz = CGSize(width: 700, height: 466)
            save("split", sz.width, sz.height, ZStack { Image(nsImage: film).resizable(); SplitOverlay(original: orig, size: sz, split: sp) })
        }
        library.settings.lab = .scan
        library.settings.ageYears = 12
        save("main_lab", 1320, 860, MainView())
        save("main_min", 1180, 760, MainView())
        save("inspector", 262, 1000, Inspector(scrolls: false).frame(maxHeight: .infinity, alignment: .top).background(Plat.face))
        for (n, k) in [("startup", RetroSound.startup), ("shutter", .shutter), ("shade", .shade), ("unshade", .unshade), ("click", .click)] {
            try? Synth.wav(Synth.samples(for: k)).write(to: dir.appendingPathComponent(n + ".wav"))
        }
        return true
    }
}

/// Startup screen with every extension loaded (for snapshots).
struct StartupScreenStatic: View {
    var body: some View {
        ZStack {
            PatternFill(pattern: Retro.shared.pattern)
            VStack(spacing: 10) {
                PixelIcon(rows: Pixels.happyCamera, scale: 4)
                Text("Welcome to Emulsion 98").font(Plat.font(20, bold: true)).foregroundStyle(Plat.ink)
                Text("Loading Photos Bridge…").font(Plat.font(11)).foregroundStyle(Plat.dark)
                PlatinumProgress(value: 0.7).frame(width: 240)
            }
            .padding(.vertical, 22).padding(.horizontal, 40).raisedPanel()
            .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
            .background(Rectangle().fill(Color.black.opacity(0.6)).offset(x: 3, y: 3))
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<StartupScreen.parade.count, id: \.self) { i in StartupScreen.parade[i].1.frame(width: 32, height: 32) }
                Spacer()
            }
            .padding(.leading, 14).padding(.bottom, 12).frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}


extension Snapshot {
    /// README screenshots: the window with only `photo` loaded (held in memory — the user's library and
    /// preferences are never touched or saved).
    static func readme(library lib: Library, out dir: URL, photo: URL) {
        active = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let retro = Retro.shared
        let saved = (retro.sounds, retro.stripOpen, retro.pattern, retro.showStartup, lib.settings, lib.stockID, lib.exportFormat, lib.destination)
        defer {
            retro.sounds = saved.0; retro.stripOpen = saved.1; retro.pattern = saved.2; retro.showStartup = saved.3
            lib.settings = saved.4; lib.stockID = saved.5; lib.exportFormat = saved.6; lib.destination = saved.7
            UserDefaults.standard.synchronize()
        }
        retro.sounds = false; retro.starting = false; retro.stripOpen = true; retro.pattern = .darkroom
        lib.settings = DevelopSettings(); lib.exportFormat = .jpeg; lib.destination = .folder
        lib.stockID = "portra400"
        lib.photos = [Photo(url: photo)]
        lib.selection = photo
        // Develop synchronously what the async renderer would show.
        guard let p = try? PhotoIO.load(photo, maxLongSide: 1400) else { return }
        let ctx = p.context(seed: PhotoIO.seed(for: photo))
        func ns(_ img: RGBImage) -> NSImage? { PhotoIO.cgImage(img).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } }
        lib.preview = ns(Developer.develop(p.image, stock: lib.stock, settings: lib.settings, context: ctx))
        lib.original = ns(PhotoIO.displayOriginal(p.image))
        lib.capture = p.capture
        let small = p.image.downscaled(toLongSide: 160)
        var thumbs: [String: NSImage] = [:]
        for s in FilmStock.catalog {
            thumbs[s.id] = ns(Developer.develop(small, stock: s, settings: lib.settings,
                                                context: DevelopContext(fullLongSide: p.fullLongSide * 160 / max(p.image.longSide, 1))))
        }
        lib.stockThumbs = thumbs
        lib.photoThumbs = [photo: ns(PhotoIO.displayOriginal(small)) ?? NSImage()]
        if let full = try? PhotoIO.load(photo) {
            let pt = CGPoint(x: 0.61, y: 0.27), size = 240
            let x = Int(CGFloat(full.image.width) * pt.x) - size / 2, y = Int(CGFloat(full.image.height) * pt.y) - size / 2
            let crop = full.image.cropped(x: x, y: y, width: size, height: size)
            let c = full.context(fullLongSide: full.image.longSide, originX: x, originY: y, seed: PhotoIO.seed(for: photo))
            lib.loupePoint = pt
            lib.loupe = ns(Developer.develop(crop, stock: lib.stock, settings: lib.settings, context: c))
        }
        lib.status = "Developed in Kodak Portra 400."
        func save<V: View>(_ name: String, _ w: CGFloat, _ h: CGFloat, _ v: V) {
            let r = ImageRenderer(content: v.environmentObject(lib).frame(width: w, height: h).environment(\.colorScheme, .light))
            r.scale = 2
            guard let cg = r.cgImage else { return }
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + ".png"))
        }
        save("window", 1320, 860, MainView())
        retro.balloons = true
        retro.tip = BalloonTip(text: "Halation. The red glow around bright lights, from light bouncing off the film base.", rect: CGRect(x: 1062, y: 405, width: 245, height: 30))
        save("balloon-help", 1320, 860, MainView())
        retro.balloons = false; retro.tip = nil
        retro.showAbout = true
        save("about", 1320, 860, MainView())
        retro.showAbout = false
        save("startup", 1000, 620, StartupScreenStatic())
        save("banner", 1280, 320, ReadmeBanner())
    }
}

/// README banner in the app's Platinum style.
struct ReadmeBanner: View {
    var body: some View {
        VStack(spacing: 0) {
            PlatinumTitleBar(title: "Emulsion 98")
            HStack(spacing: 28) {
                PixelIcon(rows: Pixels.happyCamera, scale: 7)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Emulsion 98").font(Plat.font(54, bold: true)).foregroundStyle(Plat.ink)
                    Text("Spectral film simulation for the Mac").font(Plat.font(22)).foregroundStyle(Plat.dark)
                    HStack(spacing: 10) {
                        ForEach(["Kodak", "Fujifilm", "Ilford", "CineStill"], id: \.self) { m in
                            HStack(spacing: 4) {
                                FilmCanister(maker: m, kind: m == "Ilford" ? .bw : .neg).frame(width: 22, height: 26)
                                Text(m).font(Plat.font(13)).foregroundStyle(Plat.ink)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Plat.face).overlay(Bevel(raised: true))
                            .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                        }
                    }
                    .padding(.top, 6)
                }
                Spacer()
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: .infinity)
            .background(Plat.face)
        }
        .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
        .background(Rectangle().fill(Color.black.opacity(0.55)).offset(x: 4, y: 4))
        .padding(.trailing, 6).padding(.bottom, 6)
    }
}
