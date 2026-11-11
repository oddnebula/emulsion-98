import SwiftUI
import AppKit
import FilmEngine

// Late-90s Mac OS quirks, all original artwork and synthesized sounds:
// startup screen with an extensions parade, WindowShade, Balloon Help, a wristwatch busy cursor,
// the Control Strip, desktop patterns, a safelight mode, bomb / sad-camera errors and a secret About box.

@MainActor
final class Retro: ObservableObject {
    static let shared = Retro()

    @Published var sounds: Bool { didSet { UserDefaults.standard.set(sounds, forKey: "retroSounds") } }
    @Published var balloons = false { didSet { if !balloons { tip = nil } } }
    @Published var pattern: DesktopPattern { didSet { UserDefaults.standard.set(pattern.rawValue, forKey: "desktopPattern") } }
    @Published var safelight = false
    @Published var showStartup: Bool { didSet { UserDefaults.standard.set(showStartup, forKey: "showStartup") } }
    @Published var starting: Bool
    @Published var shaded = false
    @Published var tip: BalloonTip?
    @Published var stripOpen: Bool { didSet { UserDefaults.standard.set(stripOpen, forKey: "controlStripOpen") } }
    @Published var showAbout = false
    @Published var showInfo = false
    @Published var saverOn = false
    @Published var saverMinutes: Int { didSet { UserDefaults.standard.set(saverMinutes, forKey: "saverMinutes") } }

    private init() {
        let d = UserDefaults.standard
        sounds = d.object(forKey: "retroSounds") as? Bool ?? true
        pattern = DesktopPattern(rawValue: d.string(forKey: "desktopPattern") ?? "") ?? .darkroom
        showStartup = d.object(forKey: "showStartup") as? Bool ?? true
        stripOpen = d.object(forKey: "controlStripOpen") as? Bool ?? false
        starting = d.object(forKey: "showStartup") as? Bool ?? true
        saverMinutes = d.object(forKey: "saverMinutes") as? Int ?? 5
    }

    // MARK: Sounds

    private var cache: [RetroSound: NSSound] = [:]
    func play(_ s: RetroSound) {
        guard sounds else { return }
        let snd: NSSound?
        if let c = cache[s] { snd = c } else {
            switch s {
            case .error: snd = NSSound(named: "Sosumi")
            case .done: snd = NSSound(named: "Glass")
            default: snd = NSSound(data: Synth.wav(Synth.samples(for: s)))
            }
            cache[s] = snd
        }
        snd?.stop(); snd?.play()
    }

    // MARK: WindowShade

    private var unshadedHeight: CGFloat = 860
    /// Rolls the window up into its title bar (or back down), like the Mac OS 8 WindowShade.
    func toggleShade() {
        guard let w = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        var f = w.frame
        if !shaded {
            unshadedHeight = f.height
            shaded = true
            tip = nil
            play(.shade)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                w.contentMinSize = NSSize(width: w.contentMinSize.width, height: 22)
                f.origin.y += f.height - 22; f.size.height = 22
                w.setFrame(f, display: true, animate: true)
            }
        } else {
            play(.unshade)
            f.origin.y -= unshadedHeight - f.height; f.size.height = unshadedHeight
            w.setFrame(f, display: true, animate: true)
            shaded = false
        }
    }

    func restartDarkroom() {
        starting = true
    }
}

enum RetroSound: Hashable { case startup, shutter, shade, unshade, click, error, done }

struct BalloonTip: Equatable {
    var text: String
    var rect: CGRect
}

// MARK: - Sound synthesis (original sounds, generated at runtime)

enum Synth {
    static let rate: Double = 44100

    static func samples(for s: RetroSound) -> [Float] {
        switch s {
        case .startup: return startup()
        case .shutter: return shutter()
        case .shade: return sweep(up: true)
        case .unshade: return sweep(up: false)
        case .click: return click()
        case .error, .done: return []
        }
    }

    /// Film-advance ratchet, then a strummed E♭ add9 bell chord.
    static func startup() -> [Float] {
        let n = Int(rate * 3.2)
        var out = [Float](repeating: 0, count: n)
        var rng = SystemRandomNumberGenerator()
        for c in 0..<3 { addClick(&out, at: 0.02 + Double(c) * 0.075, amp: 0.35, rng: &rng) }
        let notes: [Double] = [155.56, 233.08, 311.13, 392.00, 698.46]
        for (k, f) in notes.enumerated() {
            let start = Int((0.34 + Double(k) * 0.028) * rate)
            for p in 1...4 {
                let pf = f * Double(p) * (1 + 0.0007 * Double(p * p))
                let amp = 0.16 / pow(Double(p), 1.6) * (k == 4 ? 0.6 : 1)
                let tau = 1.5 / Double(p)
                for i in start..<n {
                    let t = Double(i - start) / rate
                    let env = min(t / 0.012, 1) * exp(-t / tau)
                    out[i] += Float(amp * env * sin(2 * .pi * pf * t + Double(k)))
                }
            }
        }
        return normalized(out, peak: 0.55)
    }

    static func shutter() -> [Float] {
        var out = [Float](repeating: 0, count: Int(rate * 0.18))
        var rng = SystemRandomNumberGenerator()
        addClick(&out, at: 0.0, amp: 0.5, rng: &rng)
        addClick(&out, at: 0.05, amp: 0.8, rng: &rng)
        for i in 0..<out.count {
            let t = Double(i) / rate - 0.05
            if t > 0 { out[i] += Float(0.35 * exp(-t / 0.025) * sin(2 * .pi * 95 * t)) }
        }
        return normalized(out, peak: 0.6)
    }

    /// Filtered-noise "fwip" for WindowShade.
    static func sweep(up: Bool) -> [Float] {
        let n = Int(rate * 0.16)
        var out = [Float](repeating: 0, count: n)
        var rng = SystemRandomNumberGenerator()
        var y: Double = 0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let a = 0.03 + 0.5 * (up ? t : 1 - t)
            let x = Double.random(in: -1...1, using: &rng)
            y += a * (x - y)
            out[i] = Float(y * sin(.pi * t))
        }
        return normalized(out, peak: 0.35)
    }

    static func click() -> [Float] {
        var out = [Float](repeating: 0, count: Int(rate * 0.03))
        for i in 0..<out.count {
            let t = Double(i) / rate
            out[i] = Float(exp(-t / 0.003) * sin(2 * .pi * 2300 * t))
        }
        return normalized(out, peak: 0.3)
    }

    static func addClick(_ out: inout [Float], at time: Double, amp: Double, rng: inout SystemRandomNumberGenerator) {
        let s = Int(time * rate)
        var y: Double = 0
        for i in 0..<Int(rate * 0.02) where s + i < out.count {
            let t = Double(i) / rate
            y += 0.45 * (Double.random(in: -1...1, using: &rng) - y)
            out[s + i] += Float(amp * exp(-t / 0.004) * y + amp * 0.5 * exp(-t / 0.006) * sin(2 * .pi * 1800 * t))
        }
    }

    static func normalized(_ s: [Float], peak: Float) -> [Float] {
        let m = s.map { abs($0) }.max() ?? 1
        return m > 0 ? s.map { $0 / m * peak } : s
    }

    /// 16-bit mono PCM WAV.
    static func wav(_ s: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(s.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for v in s { u16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32000))) }
        return d
    }
}

// MARK: - Pixel icons

struct PixelIcon: View {
    let rows: [String]
    var scale: CGFloat = 2

    static let palette: [Character: Color] = [
        "k": .black, "w": .white, "g": Color(white: 0.8), "d": Color(white: 0.5), "s": Color(white: 0.65),
        "y": Color(red: 1, green: 0.85, blue: 0.1), "r": Color(red: 0.85, green: 0.1, blue: 0.1),
        "o": Color(red: 1, green: 0.55, blue: 0.1), "n": Color(red: 0.45, green: 0.27, blue: 0.12),
        "c": Color(red: 0.35, green: 0.75, blue: 0.95), "b": Color(red: 0.15, green: 0.3, blue: 0.85),
        "m": Color(red: 0.75, green: 0.2, blue: 0.7), "G": Color(red: 0.15, green: 0.65, blue: 0.25),
        "p": Color(red: 1, green: 0.8, blue: 0.75)]

    var body: some View {
        let width = rows.map { $0.count }.max() ?? 16
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    if let c = Self.palette[ch] {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale)), with: .color(c))
                    }
                }
            }
        }
        .frame(width: CGFloat(width) * scale, height: CGFloat(rows.count) * scale)
    }
}

enum Pixels {
    /// The Happy Camera: a compact camera whose rear screen smiles back.
    static let happyCamera = [
        "................",
        "..kkkk......kk..",
        ".kssssk....kyyk.",
        "kkkkkkkkkkkkkkkk",
        "kggggggggggggggk",
        "kgkkkkkkkkkkkkgk",
        "kgkwwwwwwwwwwkgk",
        "kgkwwkwwwwkwwkgk",
        "kgkwwkwwwwkwwkgk",
        "kgkwwwwwwwwwwkgk",
        "kgkwkwwwwwwkwkgk",
        "kgkwwkkkkkkwwkgk",
        "kgkwwwwwwwwwwkgk",
        "kgkkkkkkkkkkkkgk",
        "kggggggggggggdgk",
        "kkkkkkkkkkkkkkkk"]
    static let winkCamera: [String] = {
        var r = happyCamera
        r[7] = "kgkwwkwwwwwwwkgk"; r[8] = "kgkwwkwwwkkkwkgk"
        return r
    }()
    static let sadCamera = [
        "................",
        "..kkkk......kk..",
        ".kssssk....kyyk.",
        "kkkkkkkkkkkkkkkk",
        "kggggggggggggggk",
        "kgkkkkkkkkkkkkgk",
        "kgkwkwkwwkwkwkgk",
        "kgkwwkwwwwkwwkgk",
        "kgkwkwkwwkwkwkgk",
        "kgkwwwwwwwwwwkgk",
        "kgkwwwkkkkwwwkgk",
        "kgkwwkwwwwkwwkgk",
        "kgkwwwwwwwwwwkgk",
        "kgkkkkkkkkkkkkgk",
        "kggggggggggggdgk",
        "kkkkkkkkkkkkkkkk"]
    static let bomb = [
        "..........y.....",
        ".........y.y....",
        "........k...y...",
        ".......k........",
        "....kkkkk.......",
        "...kkkkkkk......",
        "..kkwwkkkkk.....",
        ".kkwkkkkkkkk....",
        ".kkwkkkkkkkk....",
        ".kkkkkkkkkkk....",
        ".kkkkkkkkkkk....",
        ".kkkkkkkkkkk....",
        "..kkkkkkkkk.....",
        "...kkkkkkk......",
        "....kkkkk.......",
        "................"]
    static let prism = [
        "................",
        ".......kk.......",
        "......kwwk......",
        "......kwwk......",
        ".....kwwgwk.....",
        "ww..kwwwgwwk....",
        "..wwkwwwwgwkrrr.",
        "....wwwwwwgkooo.",
        "...kwwwwwwwgkyyy",
        "...kwwwwwwwwkGGG",
        "..kwwwwwwwwwgkbb",
        "..kwwwwwwwwwwkmm",
        ".kkkkkkkkkkkkkk.",
        "................"]
    static let crystal = [
        "................",
        ".......kk.......",
        "......kwgk......",
        ".....kwwggk.....",
        "....kwwwgggk....",
        "...kwwwwggggk...",
        "..kwwwwwgggggk..",
        ".kwwwwwwggggggk.",
        ".kdddddddsssssk.",
        "..kddddddssssk..",
        "...kdddddsssk...",
        "....kddddssk....",
        ".....kdddsk.....",
        "......kddk......",
        ".......kk.......",
        "................"]
    static let grain = [
        "kkkkkkkkkkkkkkkk",
        "kwwwwwwwwwwwwwwk",
        "kwkwwdwwkwwwdwwk",
        "kwwwwwwkwwdwwwwk",
        "kwdwwkwwwwwwkwwk",
        "kwwwwwwdwkwwwwwk",
        "kwkwwwwwwwwdwkwk",
        "kwwwdwkwwwwwwwwk",
        "kwwwwwwwwkwdwwwk",
        "kwkwwdwwwwwwwkwk",
        "kwwwwwwkwdwwwwwk",
        "kwdwkwwwwwwkwwwk",
        "kwwwwwwdwwwwwdwk",
        "kwwkwwwwwkwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kkkkkkkkkkkkkkkk"]
    static let coupler = [
        "................",
        "................",
        "..kkkkk.........",
        ".kcccccck.......",
        "kcck...kcckkkk..",
        "kck....kkmmmmmk.",
        "kck...kmmk...kmk",
        "kcck..kmmk...kmk",
        ".kcccckmck..kmmk",
        "..kkkkkmmkkkmmk.",
        "......kmmmmmmk..",
        ".......kkkkkk...",
        "................",
        "................"]
    static let halation = [
        "................",
        ".....rrrrrr.....",
        "...rroooooorr...",
        "..roo......oor..",
        ".ro...kkkk...or.",
        ".ro..kwwwwk..or.",
        "ro..kwwwwwwk..or",
        "ro..kwwwwwwk..or",
        "ro..kwwwwwwk..or",
        "ro..kwwwwwwk..or",
        ".ro..kwwwwk..or.",
        ".ro...kkkk...or.",
        "..roo......oor..",
        "...rroooooorr...",
        ".....rrrrrr.....",
        "................"]
    static let safelight = [
        "......kkkk......",
        ".....krrrrk.....",
        "....krrwrrrk....",
        "...krrwrrrrrk...",
        "...krrrrrrrrk...",
        "...krrrrrrrrk...",
        "....krrrrrrk....",
        ".....krrrrk.....",
        "......kddk......",
        "......kggk......",
        "......kddk......",
        "......kggk......",
        ".......kk.......",
        "..r..........r..",
        ".r............r.",
        "................"]
    static let photo = [
        "kkkkkkkkkkkkkkkk",
        "knnnnnnnnnnnnnnk",
        "knccccccccccccnk",
        "kncccccccyycccnk",
        "knccccccyyyyccnk",
        "kncccccccyycccnk",
        "knccccccccccccnk",
        "kncccGccccccccnk",
        "knccGGGcccGcccnk",
        "kncGGGGGcGGGccnk",
        "knGGGGGGGGGGGGnk",
        "knnnnnnnnnnnnnnk",
        "kkkkkkkkkkkkkkkk"]
    static let paper = [
        "kkkkkkkkkkk.....",
        "kwwwwwwwwwkk....",
        "kwwwwwwwwwkwk...",
        "kwpppppppwkwwk..",
        "kwpooooppwkkkkk.",
        "kwpooooopwwwwwk.",
        "kwppoooopppppwk.",
        "kwppppppppppppwk",
        "kwppppppppppppwk",
        "kwpwwwwwwwwwppwk",
        "kwppppppppppppwk",
        "kwwwwwwwwwwwwwwk",
        "kkkkkkkkkkkkkkkk"]
    static let speaker = [
        "......kk..",
        ".....kgk..",
        "kkkkkggk.k",
        "kgggkggk..",
        "kgggkggkk.",
        "kgggkggk..",
        "kkkkkggk.k",
        ".....kgk..",
        "......kk.."]
    static let balloon = [
        "..kkkkkk..",
        ".kwwwwwwk.",
        "kwwkkkwwwk",
        "kwwwwkwwwk",
        "kwwwkwwwwk",
        ".kwwwwwwk.",
        "..kkwkkk..",
        "...kk.....",
        "...k......"]
    static let bulb = [
        "...kkkk...",
        "..krrrrk..",
        ".krwrrrrk.",
        ".krrrrrrk.",
        "..krrrrk..",
        "...kddk...",
        "...kggk...",
        "...kddk...",
        "....kk...."]
}

// MARK: - Desktop patterns

enum DesktopPattern: String, CaseIterable, Identifiable {
    case darkroom, platinum, bondi, filmstrip, houndstooth, safelight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .darkroom: "Darkroom Grey"; case .platinum: "Platinum Dither"; case .bondi: "Blueberry Dots"
        case .filmstrip: "Film Strip"; case .houndstooth: "Houndstooth"; case .safelight: "Safelight Red"
        }
    }

    /// One tile of the pattern (drawn pixel by pixel).
    var tile: NSImage {
        switch self {
        case .darkroom: return Self.tile(8, 8) { _, _ in NSColor(white: 0.2, alpha: 1) }
        case .platinum: return Self.tile(4, 4) { x, y in (x + y) % 2 == 0 ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 0.17, alpha: 1) }
        case .bondi:
            return Self.tile(8, 8) { x, y in
                (x == 1 && y == 1) || (x == 5 && y == 5) ? NSColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1)
                    : NSColor(red: 0.1, green: 0.2, blue: 0.45, alpha: 1)
            }
        case .filmstrip:
            return Self.tile(16, 40) { x, y in
                let hole = (y >= 3 && y < 8 || y >= 32 && y < 37) && x >= 4 && x < 11
                return hole ? NSColor(white: 0.75, alpha: 1) : NSColor(red: 0.2, green: 0.13, blue: 0.07, alpha: 1)
            }
        case .houndstooth:
            let m = ["kkkkw...", "kkkww...", "kkkk.w..", "kkkk..w.", "kkkkkkkk", ".kkkw...", "..kkw...", "...kw..."]
            return Self.tile(8, 8) { x, y in
                let ch = Array(m[y])[x]
                return ch == "k" ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.3, alpha: 1)
            }
        case .safelight:
            return Self.tile(4, 4) { x, y in (x + y) % 2 == 0 ? NSColor(red: 0.3, green: 0.02, blue: 0.02, alpha: 1) : NSColor(red: 0.2, green: 0.0, blue: 0.0, alpha: 1) }
        }
    }

    private static func tile(_ w: Int, _ h: Int, _ color: @escaping (Int, Int) -> NSColor) -> NSImage {
        let px: CGFloat = 2
        return NSImage(size: NSSize(width: CGFloat(w) * px, height: CGFloat(h) * px), flipped: true) { _ in
            for y in 0..<h { for x in 0..<w {
                color(x, y).setFill()
                NSRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px).fill()
            } }
            return true
        }
    }
}

struct PatternFill: View {
    let pattern: DesktopPattern
    var body: some View {
        Image(nsImage: pattern.tile).resizable(resizingMode: .tile).interpolation(.none)
    }
}

// MARK: - Startup screen

final class Counter: ObservableObject { @Published var n = 0 }

struct StartupScreen: View {
    @ObservedObject var retro = Retro.shared
    @StateObject private var count = Counter()

    static let parade: [(String, AnyView)] = [
        ("Spectral Manager", AnyView(PixelIcon(rows: Pixels.prism))),
        ("Silver Halide Enabler", AnyView(PixelIcon(rows: Pixels.crystal))),
        ("Grain Control", AnyView(PixelIcon(rows: Pixels.grain))),
        ("DIR Coupler Extension", AnyView(PixelIcon(rows: Pixels.coupler))),
        ("Halation", AnyView(PixelIcon(rows: Pixels.halation))),
        ("Safelight", AnyView(PixelIcon(rows: Pixels.safelight))),
        ("Photos Bridge", AnyView(PixelIcon(rows: Pixels.photo))),
        ("Endura Paper", AnyView(PixelIcon(rows: Pixels.paper))),
        ("Film Loader", AnyView(FilmCanister(maker: "Kodak", kind: .neg).frame(width: 28, height: 32))),
        ("Camera Profiles", AnyView(PixelIcon(rows: Pixels.happyCamera))),
    ]

    var body: some View {
        if retro.starting {
            ZStack {
                PatternFill(pattern: retro.pattern)
                VStack(spacing: 10) {
                    PixelIcon(rows: Pixels.happyCamera, scale: 4)
                    Text("Welcome to Emulsion 98").font(Plat.font(20, bold: true)).foregroundStyle(Plat.ink)
                    Text(count.n < Self.parade.count ? "Loading \(Self.parade[count.n].0)…" : "Starting up…")
                        .font(Plat.font(11)).foregroundStyle(Plat.dark)
                    PlatinumProgress(value: Double(count.n) / Double(Self.parade.count)).frame(width: 240)
                }
                .padding(.vertical, 22).padding(.horizontal, 40)
                .raisedPanel()
                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                .background(Rectangle().fill(Color.black.opacity(0.6)).offset(x: 3, y: 3))

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<min(count.n, Self.parade.count), id: \.self) { i in
                        Self.parade[i].1.frame(width: 32, height: 32).help(Self.parade[i].0)
                    }
                    Spacer()
                }
                .padding(.leading, 14).padding(.bottom, 12)
                .frame(maxHeight: .infinity, alignment: .bottom)

                Text("Click to skip").font(Plat.font(10)).foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(12)
            }
            .contentShape(Rectangle())
            .onTapGesture { finish() }
            .onAppear(perform: run)
            .transition(.opacity)
        }
    }

    func run() {
        count.n = 0
        retro.play(.startup)
        Timer.scheduledTimer(withTimeInterval: 0.26, repeats: true) { t in
            MainActor.assumeIsolated {
                guard retro.starting else { t.invalidate(); return }
                if count.n < Self.parade.count { count.n += 1 }
                else { t.invalidate(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finish() } }
            }
        }
    }

    func finish() { withAnimation(.easeOut(duration: 0.25)) { retro.starting = false } }
}

// MARK: - Balloon Help

final class RectHolder: ObservableObject { var rect: CGRect = .zero }

struct BalloonModifier: ViewModifier {
    let text: String
    @StateObject private var box = RectHolder()

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                let r = g.frame(in: .named("window"))
                Color.clear
                    .onAppear { box.rect = r }
                    .onChange(of: r) { _, n in box.rect = n }
            })
            .onHover { inside in
                let retro = Retro.shared
                guard retro.balloons else { return }
                if inside { retro.tip = BalloonTip(text: text, rect: box.rect) }
                else if retro.tip?.text == text { retro.tip = nil }
            }
    }
}

extension View {
    /// Classic Balloon Help: shown on hover while Help ▸ Show Balloons is on.
    func balloon(_ text: String) -> some View { modifier(BalloonModifier(text: text)) }
}

struct BalloonLayer: View {
    @ObservedObject var retro = Retro.shared

    var body: some View {
        GeometryReader { g in
            if retro.balloons, let tip = retro.tip {
                let width: CGFloat = 230, tail: CGFloat = 16
                let tipX = min(max(tip.rect.midX, 20), g.size.width - 20)
                let above = tip.rect.minY > 140
                let tipY = above ? tip.rect.minY + 3 : tip.rect.maxY - 3
                let x = min(max(tipX - width + 30, 8), g.size.width - width - 8)
                ZStack(alignment: .topLeading) {
                    Color.clear
                    Text(tip.text)
                        .font(Plat.font(11)).foregroundStyle(Plat.ink)
                        .frame(width: width - 24, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 1, green: 1, blue: 0.9)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Plat.ink, lineWidth: 1))
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)).offset(x: 2, y: 2))
                        .alignmentGuide(.leading) { _ in -x }
                        .alignmentGuide(.top) { d in above ? d[.bottom] - (tipY - tail) : -(tipY + tail) }
                    // the tail
                    Path { p in
                        let by = above ? tipY - tail - 1 : tipY + tail + 1
                        p.move(to: CGPoint(x: tipX - 4, y: by)); p.addLine(to: CGPoint(x: tipX, y: tipY))
                        p.addLine(to: CGPoint(x: tipX + 12, y: by))
                    }
                    .fill(Color(red: 1, green: 1, blue: 0.9))
                    Path { p in
                        let by = above ? tipY - tail : tipY + tail
                        p.move(to: CGPoint(x: tipX - 4, y: by)); p.addLine(to: CGPoint(x: tipX, y: tipY))
                        p.addLine(to: CGPoint(x: tipX + 12, y: by))
                    }
                    .stroke(Plat.ink, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Wristwatch busy cursor

@MainActor
enum WatchCursor {
    private static var timer: Timer?
    private static var frame = 0
    private static let cursors: [NSCursor] = (0..<8).map { make(Double($0) * .pi / 4) }

    static func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            MainActor.assumeIsolated {
                frame += 1
                if NSApp.isActive, let w = NSApp.keyWindow, w.frame.contains(NSEvent.mouseLocation) { cursors[frame % 8].set() }
            }
        }
    }

    static func stop() {
        timer?.invalidate(); timer = nil
        NSCursor.arrow.set()
    }

    private static func make(_ angle: Double) -> NSCursor {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            NSRect(x: 5, y: 0, width: 6, height: 3).fill(); NSRect(x: 5, y: 13, width: 6, height: 3).fill()
            let face = NSBezierPath(ovalIn: NSRect(x: 2, y: 2.5, width: 12, height: 11))
            NSColor.white.setFill(); face.fill()
            NSColor.black.setStroke(); face.lineWidth = 1.5; face.stroke()
            NSRect(x: 14, y: 7, width: 1.5, height: 2).fill()
            let c = NSPoint(x: 8, y: 8)
            let hands = NSBezierPath()
            hands.move(to: c); hands.line(to: NSPoint(x: c.x + 4 * sin(angle), y: c.y - 4 * cos(angle)))
            hands.move(to: c); hands.line(to: NSPoint(x: c.x + 2.6 * sin(angle / 12 + 1), y: c.y - 2.6 * cos(angle / 12 + 1)))
            hands.lineWidth = 1.2; hands.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }
}

// MARK: - Control Strip

struct ControlStrip: View {
    @ObservedObject var retro = Retro.shared
    @EnvironmentObject var lib: Library

    var body: some View {
        HStack(spacing: 0) {
            if retro.stripOpen {
                module(PixelIcon(rows: Pixels.speaker, scale: 2), on: retro.sounds,
                       help: "Sound effects are \(retro.sounds ? "on" : "off"). Click to turn them \(retro.sounds ? "off" : "on").") {
                    retro.sounds.toggle(); retro.play(.click)
                }
                module(PixelIcon(rows: Pixels.balloon, scale: 2), on: retro.balloons,
                       help: "Balloon Help. When it is on, point at anything to find out what it does.") {
                    retro.balloons.toggle(); retro.play(.click)
                }
                module(PixelIcon(rows: Pixels.bulb, scale: 2), on: retro.safelight,
                       help: "Safelight. Bathes the darkroom in red light. Your photos are safe; this is only for the mood.") {
                    retro.safelight.toggle(); retro.play(.click)
                }
                menuModule(help: "Desktop pattern behind the photo.") {
                    ForEach(DesktopPattern.allCases) { p in
                        Button((p == retro.pattern ? "✓ " : "   ") + p.label) { retro.pattern = p }
                    }
                } icon: {
                    PatternFill(pattern: retro.pattern).frame(width: 18, height: 14)
                        .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                }
                menuModule(help: "Grain amount, quickly.") {
                    ForEach([0, 50, 100, 150, 200], id: \.self) { v in
                        Button("\(Int((lib.settings.grain * 100).rounded()) == v ? "✓ " : "   ")\(v)% grain") { lib.settings.grain = Float(v) / 100 }
                    }
                } icon: { PixelIcon(rows: Array(Pixels.grain.prefix(9)).map { String($0.prefix(10)) }, scale: 1.6) }
                menuModule(help: "Film format: bigger film, finer grain.") {
                    ForEach(FilmFormat.allCases) { f in
                        Button((f == lib.settings.format ? "✓ " : "   ") + f.label) { lib.settings.format = f }
                    }
                } icon: {
                    Text({ switch lib.settings.format { case .halfFrame: "½"; case .mm35: "35"; case .lf45: "4×5"; default: "120" } }()).font(Plat.font(9, bold: true)).foregroundStyle(Plat.ink)
                }
            }
            // the tab
            Button {
                retro.stripOpen.toggle(); retro.play(.click)
            } label: {
                ZStack {
                    Rectangle().fill(Plat.mid)
                    VStack(spacing: 2) { ForEach(0..<5) { _ in Rectangle().fill(Plat.dark).frame(width: 5, height: 1) } }
                }
                .frame(width: 11, height: 20)
                .overlay(Bevel(raised: true))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 5, topTrailingRadius: 5)
                    .stroke(Plat.ink, lineWidth: 1))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 5, topTrailingRadius: 5))
            }
            .buttonStyle(.plain)
            .balloon("Control Strip. Click the tab to \(retro.stripOpen ? "tuck it away" : "pull it out").")
        }
        .background(Plat.face)
        .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: retro.stripOpen ? 1 : 0))
        .background(Rectangle().fill(Color.black.opacity(0.4)).offset(x: 1, y: 1))
    }

    func module<I: View>(_ icon: I, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.frame(width: 30, height: 20)
                .background(on ? Plat.highlight : Plat.face)
                .overlay(Bevel(raised: !on))
                .overlay(Rectangle().fill(Plat.shade).frame(width: 1), alignment: .trailing)
                .opacity(on ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .balloon(help)
    }

    func menuModule<M: View, I: View>(help: String, @ViewBuilder _ items: () -> M, @ViewBuilder icon: () -> I) -> some View {
        Menu { items() } label: {
            icon().frame(width: 30, height: 20)
                .background(Plat.face)
                .overlay(Bevel(raised: true))
                .overlay(Rectangle().fill(Plat.shade).frame(width: 1), alignment: .trailing)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .frame(width: 30, height: 20)
        .balloon(help)
    }
}

// MARK: - About box (with a secret)

final class AboutState: ObservableObject {
    @Published var clicks = 0
    @Published var credits = false
    @Published var started = Date()
}

struct AboutBox: View {
    @ObservedObject var retro = Retro.shared
    @StateObject private var st = AboutState()

    static let creditLines = [
        "EMULSION 98", "", "The Darkroom Team", "",
        "Silver Halide ............ Lead Crystal", "Gelatin ................. Binder", "Cyan Coupler ............. Red Layer",
        "Magenta Coupler .......... Green Layer", "Yellow Coupler ........... Blue Layer", "The Orange Mask .......... Itself",
        "DIR Inhibitors ........... Edge Effects", "Halation ................. Glow", "", "Measured film data",
        "spektrafilm by Andrea Volpato", "(CC BY-SA 4.0)", "", "Spectral basis after Mallett & Yuksel", "",
        "Catering", "Fixer, stop bath and coffee", "", "No film was harmed", "in the making of this software.", "",
        "Made on a Mac.", "", "", "Not affiliated with Kodak, Fujifilm,", "Ilford, CineStill or Apple."]

    var body: some View {
        if retro.showAbout {
            ZStack {
                Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { close() }
                VStack(spacing: 0) {
                    MiniTitleBar(title: "About Emulsion 98") { close() }
                    HStack(alignment: .top, spacing: 16) {
                        PixelIcon(rows: st.clicks % 2 == 1 ? Pixels.winkCamera : Pixels.happyCamera, scale: 4)
                            .onTapGesture {
                                st.clicks += 1
                                if st.clicks >= 3 && !st.credits { st.credits = true; st.started = Date(); retro.play(.startup) }
                                else { retro.play(.click) }
                            }
                            .balloon("The Happy Camera. It is very pleased to see you. It likes being clicked.")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Emulsion 98").font(Plat.font(20, bold: true)).foregroundStyle(Plat.ink)
                            Text("Version 1.2 · Darkroom Edition").font(Plat.font(11)).foregroundStyle(Plat.dark)
                            Rectangle().fill(Plat.shade).frame(height: 1).padding(.vertical, 4)
                            infoRow("Built-in Memory:", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                            infoRow("Film stocks:", "\(FilmStock.catalog.count) emulsions")
                            infoRow("Spectral grid:", "380–780 nm in 5 nm steps")
                            infoRow("Processors:", "\(ProcessInfo.processInfo.activeProcessorCount) busy darkroom assistants")
                        }
                    }
                    .padding(16)
                    MemoryBars().padding(.horizontal, 16)
                    Group {
                        if st.credits {
                            TimelineView(.animation) { tl in
                                let t = tl.date.timeIntervalSince(st.started)
                                let y = 110 - CGFloat(t) * 22
                                VStack(spacing: 2) {
                                    ForEach(Array(Self.creditLines.enumerated()), id: \.offset) { _, l in
                                        Text(l).font(Plat.font(11, bold: l == "EMULSION 98")).foregroundStyle(Color(red: 0.6, green: 1, blue: 0.6))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .offset(y: y.truncatingRemainder(dividingBy: CGFloat(Self.creditLines.count) * 15 + 110) + (y < -CGFloat(Self.creditLines.count) * 15 ? CGFloat(Self.creditLines.count) * 15 + 110 : 0))
                            }
                            .frame(height: 110).clipped()
                            .background(Color.black)
                        } else {
                            Text("Measured film data: spektrafilm profiles by Andrea Volpato, CC BY-SA 4.0. Not affiliated with Kodak, Fujifilm, Ilford or CineStill. Stock names identify the look being emulated.")
                                .font(Plat.font(10)).foregroundStyle(Plat.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                                .padding(8)
                                .background(Color.white)
                        }
                    }
                    .padding(2).sunkenWell(.white)
                    .padding(16)
                    Button("Close") { close() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
                }
                .frame(width: 460)
                .background(Plat.face)
                .overlay(Bevel(raised: true).padding(1))
                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                .background(Rectangle().fill(Color.black.opacity(0.6)).offset(x: 3, y: 3))
            }
        }
    }

    func infoRow(_ a: String, _ b: String) -> some View {
        HStack(spacing: 6) {
            Text(a).font(Plat.font(11, bold: true)).foregroundStyle(Plat.ink).frame(width: 110, alignment: .leading)
            Text(b).font(Plat.font(11)).foregroundStyle(Plat.ink)
        }
    }

    func close() { retro.showAbout = false; st.clicks = 0; st.credits = false }
}

/// "About This Computer"-style memory bars: how much this app is using right now.
struct MemoryBars: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let used = Double(Self.footprint())
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            HStack(spacing: 8) {
                FilmCanister(maker: "Kodak", kind: .neg).frame(width: 16, height: 18)
                Text("Emulsion 98").font(Plat.font(11)).foregroundStyle(Plat.ink).frame(width: 82, alignment: .leading)
                Text(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory))
                    .font(Plat.font(11)).foregroundStyle(Plat.ink).frame(width: 64, alignment: .trailing)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white)
                        Rectangle().fill(Plat.accent).frame(width: max(3, g.size.width * CGFloat(min(used / total * 8, 1))))
                    }
                    .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                }
                .frame(height: 10)
            }
        }
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

/// Small pinstriped title bar for floating windoids.
struct MiniTitleBar: View {
    let title: String
    let onClose: () -> Void
    var body: some View {
        ZStack {
            Plat.face
            Canvas { ctx, size in
                for y in stride(from: 4.0, to: size.height - 4, by: 2) {
                    ctx.fill(Path(CGRect(x: 4, y: y, width: size.width - 8, height: 1)), with: .color(Plat.shade))
                    ctx.fill(Path(CGRect(x: 5, y: y + 1, width: size.width - 9, height: 1)), with: .color(Plat.light))
                }
            }
            HStack {
                Button(action: onClose) {
                    ZStack { Rectangle().fill(Plat.face); Bevel(raised: true).padding(1); Rectangle().strokeBorder(Plat.ink, lineWidth: 1) }
                        .frame(width: 13, height: 13).background(Plat.face.padding(-3))
                }
                .buttonStyle(.plain).padding(.leading, 9)
                Spacer()
            }
            Text(title).font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink).padding(.horizontal, 8).background(Plat.face)
        }
        .frame(height: 22)
        .overlay(Rectangle().fill(Plat.ink).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Sad Camera

struct SadCameraView: View {
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            PixelIcon(rows: Pixels.sadCamera, scale: 4)
            Text(String(format: "%08X  %08X", 0x0000_000F, UInt32(truncatingIfNeeded: message.hashValue)))
                .font(.custom("Monaco", size: 11)).foregroundStyle(.white)
            Text(message).font(Plat.font(11)).foregroundStyle(Color(white: 0.8))
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
    }
}
