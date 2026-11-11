import SwiftUI
import AppKit
import FilmEngine

// MARK: - Get Info

struct GetInfoBox: View {
    @EnvironmentObject var lib: Library
    @ObservedObject var retro = Retro.shared

    var body: some View {
        if retro.showInfo, let url = lib.selection {
            ZStack {
                Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { retro.showInfo = false }
                VStack(spacing: 0) {
                    MiniTitleBar(title: "\(url.lastPathComponent) Info") { retro.showInfo = false }
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Color.black
                            if let t = lib.photoThumbs[url] { Image(nsImage: t).resizable().aspectRatio(contentMode: .fit) }
                        }
                        .frame(width: 96, height: 72)
                        .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).font(Plat.font(13, bold: true)).foregroundStyle(Plat.ink).lineLimit(1)
                            Text(kind(url)).font(Plat.font(11)).foregroundStyle(Plat.dark)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    Rectangle().fill(Plat.shade).frame(height: 1).padding(.horizontal, 14)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(rows(url), id: \.0) { r in
                            HStack(alignment: .top, spacing: 8) {
                                Text(r.0).font(Plat.font(11, bold: true)).foregroundStyle(Plat.ink).frame(width: 96, alignment: .trailing)
                                Text(r.1).font(Plat.font(11)).foregroundStyle(Plat.ink).fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    Button("Close") { retro.showInfo = false }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
                }
                .frame(width: 400)
                .background(Plat.face)
                .overlay(Bevel(raised: true).padding(1))
                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                .background(Rectangle().fill(Color.black.opacity(0.6)).offset(x: 3, y: 3))
            }
        }
    }

    func kind(_ url: URL) -> String {
        let raw = PhotoIO.isRAW(url)
        return "\(raw ? "Camera RAW" : url.pathExtension.uppercased()) photo\(lib.isFromPhotos(url) ? " · from Photos" : "")"
    }

    func rows(_ url: URL) -> [(String, String)] {
        var r: [(String, String)] = []
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs?[.size] as? Int64 { r.append(("Size:", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))) }
        r.append(("Where:", url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")))
        if let d = attrs?[.creationDate] as? Date { r.append(("Created:", d.formatted(date: .abbreviated, time: .shortened))) }
        if let c = lib.capture {
            r.append(("Camera:", c.cameraName + (c.profileName != "Generic" ? " (tuned profile)" : "")))
            if let l = c.lens, !l.isEmpty { r.append(("Lens:", l)) }
            if !c.exposureSummary.isEmpty { r.append(("Exposure:", c.exposureSummary)) }
            if let k = c.asShotKelvin { r.append(("Scene light:", "\(Int(k)) K as shot")) }
            if let cf = c.cropFactor { r.append(("Sensor:", String(format: "crop factor %.1f×", cf))) }
        }
        let s = lib.settings
        r.append(("Film:", "\(lib.stock.displayName), ISO \(lib.stock.iso)"))
        var dev = [s.format.label]
        if abs(s.exposure) > 0.05 { dev.append(String(format: "%+.1f EV", s.exposure)) }
        if abs(s.push) > 0.05 { dev.append(String(format: "push %+.1f", s.push)) }
        if lib.stock.kind == .colorNegative { dev.append(s.lab.label.lowercased()) }
        if s.agitation != .continuous { dev.append(s.agitation.rawValue + " agitation") }
        if s.filter != .none { dev.append(s.filter.label + " filter") }
        if s.crossProcess && lib.stock.crossProcessed != nil { dev.append("cross-processed in C-41") }
        if s.redscale && lib.stock.kind == .colorNegative { dev.append("redscale") }
        if lib.stock.kind == .blackWhite && abs(s.paperGrade - 2) > 0.1 { dev.append("paper grade " + Multigrade.label(s.paperGrade)) }
        if abs(s.ccYellow) >= 0.5 || abs(s.ccMagenta) >= 0.5 { dev.append(String(format: "%+.0fY %+.0fM", s.ccYellow, s.ccMagenta)) }
        if abs(s.printExposure) >= 0.02 { dev.append(String(format: "print %+.2f stops", s.printExposure)) }
        if s.preflash >= 0.01 { dev.append(String(format: "pre-flash %.0f%%", s.preflash * 100)) }
        if s.ageYears >= 0.5 { dev.append(String(format: "%.0f years expired (%@)", s.ageYears, s.storage.label.lowercased())) }
        if lib.stock.kind == .blackWhite && s.enlarger == .condenser { dev.append("condenser enlarger") }
        if s.printAge >= 0.5 { dev.append(String(format: "%.0f years old, %@", s.printAge, s.keeping.label.lowercased())) }
        r.append(("Development:", dev.joined(separator: " · ")))
        return r
    }
}

// MARK: - Split compare

final class SplitState: ObservableObject {
    @Published var on = false
    @Published var pos: CGFloat = 0.5
}

/// Original on the left, film on the right, with a draggable divider.
struct SplitOverlay: View {
    let original: NSImage
    let size: CGSize
    @ObservedObject var split: SplitState

    var body: some View {
        let x = size.width * split.pos
        ZStack(alignment: .topLeading) {
            Image(nsImage: original).resizable().interpolation(.high)
                .frame(width: size.width, height: size.height)
                .mask(alignment: .leading) { Rectangle().frame(width: x) }
            Rectangle().fill(Color.white).frame(width: 1, height: size.height).offset(x: x - 0.5)
            Rectangle().fill(Color.black).frame(width: 1, height: size.height).offset(x: x + 0.5)
            // knob
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Plat.face)
                Bevel(raised: true).padding(1)
                RoundedRectangle(cornerRadius: 3).strokeBorder(Plat.ink, lineWidth: 1)
                HStack(spacing: 2) {
                    Triangle(up: true).fill(Plat.ink).frame(width: 4, height: 6).rotationEffect(.degrees(-90))
                    Triangle(up: true).fill(Plat.ink).frame(width: 4, height: 6).rotationEffect(.degrees(90))
                }
            }
            .frame(width: 20, height: 28)
            .offset(x: x - 10, y: size.height / 2 - 14)
            Text("ORIGINAL").font(Plat.font(9, bold: true)).foregroundStyle(Plat.ink)
                .padding(.horizontal, 4).padding(.vertical, 1).background(Plat.highlight)
                .overlay(Rectangle().strokeBorder(Plat.ink)).offset(x: 6, y: 6)
                .opacity(split.pos > 0.12 ? 1 : 0)
            Text("FILM").font(Plat.font(9, bold: true)).foregroundStyle(Plat.ink)
                .padding(.horizontal, 4).padding(.vertical, 1).background(Plat.highlight)
                .overlay(Rectangle().strokeBorder(Plat.ink)).offset(x: size.width - 38, y: 6)
                .opacity(split.pos < 0.9 ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle().size(width: 24, height: size.height).offset(x: x - 12))
        .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
            split.pos = min(max(v.location.x / max(size.width, 1), 0), 1)
        })
        .balloon("Split view. Drag the divider: the original digital photo is on the left, the film on the right.")
    }
}

// MARK: - Darkroom Saver (idle screen saver)

@MainActor
final class IdleWatcher {
    static let shared = IdleWatcher()
    private var last = Date()
    private var monitor: Any?
    private var timer: Timer?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]) { e in
            MainActor.assumeIsolated {
                IdleWatcher.shared.last = Date()
                if Retro.shared.saverOn { Retro.shared.saverOn = false }
            }
            return e
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let r = Retro.shared
                guard r.saverMinutes > 0, !r.saverOn, !r.starting else { return }
                if Date().timeIntervalSince(IdleWatcher.shared.last) > Double(r.saverMinutes) * 60 { r.saverOn = true }
            }
        }
    }
}

struct DarkroomSaver: View {
    @ObservedObject var retro = Retro.shared
    static let start = Date()

    var body: some View {
        if retro.saverOn {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(Self.start)
                Canvas { ctx, size in
                    // a faint safelight glow
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .radialGradient(Gradient(colors: [Color(red: 0.35, green: 0.02, blue: 0.02), .black]),
                                                   center: CGPoint(x: size.width / 2, y: -60), startRadius: 0, endRadius: 420))
                    for i in 0..<14 {
                        let fi = Double(i)
                        let speed = 26 + (fi * 37).truncatingRemainder(dividingBy: 40)
                        let span = Double(size.width + size.height + 200)
                        let d = (t * speed + fi * 211).truncatingRemainder(dividingBy: span)
                        // drift diagonally from top-right to bottom-left, like falling film
                        let x = Double(size.width) + 100 - d
                        let y = -100 + d * 0.55 + (fi * 97).truncatingRemainder(dividingBy: Double(size.height))
                        let yy = y.truncatingRemainder(dividingBy: Double(size.height) + 200) - 100
                        var c = ctx
                        c.translateBy(x: x, y: yy)
                        c.rotate(by: .degrees(sin(t * 0.7 + fi) * 25))
                        c.scaleBy(x: 1 + 0.5 * (fi.truncatingRemainder(dividingBy: 3)), y: 1 + 0.5 * (fi.truncatingRemainder(dividingBy: 3)))
                        if let s = c.resolveSymbol(id: i % 3) { c.draw(s, at: .zero) }
                    }
                } symbols: {
                    FilmCanister(maker: "Kodak", kind: .neg).frame(width: 34, height: 40).tag(0)
                    FilmCanister(maker: "Fujifilm", kind: .neg).frame(width: 34, height: 40).tag(1)
                    PixelIcon(rows: Pixels.happyCamera, scale: 2).tag(2)
                }
                .background(Color.black)
            }
            .overlay(alignment: .bottom) {
                Text("Darkroom Saver — move the mouse to return").font(Plat.font(10)).foregroundStyle(Color(white: 0.35)).padding(10)
            }
            .contentShape(Rectangle())
            .onTapGesture { retro.saverOn = false }
            .transition(.opacity)
        }
    }
}
