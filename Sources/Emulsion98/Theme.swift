import SwiftUI
import AppKit

/// "Platinum" palette and controls, drawn by hand in the spirit of late-90s Mac OS.
enum Plat {
    static let face = Color(white: 0.867)        // #DDDDDD window face
    static let light = Color.white
    static let mid = Color(white: 0.733)         // #BBBBBB
    static let shade = Color(white: 0.6)         // #999999
    static let dark = Color(white: 0.4)          // #666666
    static let ink = Color.black
    static let well = Color(white: 0.933)
    static let photoWell = Color(white: 0.2)
    static let accent = Color(red: 0.4, green: 0.4, blue: 0.8)      // #6666CC
    static let highlight = Color(red: 0.8, green: 0.8, blue: 1.0)   // #CCCCFF

    static func font(_ size: CGFloat = 12, bold: Bool = false) -> Font {
        let f = Font.custom("Geneva", size: size)
        return bold ? f.bold() : f
    }
}

// MARK: - Bevels

struct Bevel: View {
    var raised = true
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0.5, y: h - 0.5)); p.addLine(to: CGPoint(x: 0.5, y: 0.5)); p.addLine(to: CGPoint(x: w - 0.5, y: 0.5))
                }.stroke(raised ? Plat.light : Plat.shade, lineWidth: 1)
                Path { p in
                    p.move(to: CGPoint(x: w - 0.5, y: 0.5)); p.addLine(to: CGPoint(x: w - 0.5, y: h - 0.5)); p.addLine(to: CGPoint(x: 0.5, y: h - 0.5))
                }.stroke(raised ? Plat.shade : Plat.light, lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Raised platinum surface.
    func raisedPanel() -> some View {
        background(Plat.face, ignoresSafeAreaEdges: []).overlay(Bevel(raised: true))
    }
    /// Sunken well with a dark inner line, like a list box.
    func sunkenWell(_ fill: Color = Plat.well) -> some View {
        background(fill, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().strokeBorder(Plat.ink.opacity(0.85), lineWidth: 1).padding(1))
            .overlay(Bevel(raised: false))
    }
}

// MARK: - Buttons

struct PlatinumButtonStyle: ButtonStyle {
    var isDefault = false
    var minWidth: CGFloat = 64
    func makeBody(configuration: Configuration) -> some View {
        PlatinumButtonBody(configuration: configuration, isDefault: isDefault, minWidth: minWidth)
    }
}

private struct PlatinumButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isDefault: Bool
    let minWidth: CGFloat
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Plat.font(12))
            .foregroundStyle(!enabled ? Plat.shade : (pressed ? Color.white : Plat.ink))
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(pressed ? Plat.dark : Plat.face)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .inset(by: 1.5)
                    .stroke(LinearGradient(colors: pressed ? [Plat.ink.opacity(0.5), Plat.mid] : [Plat.light, Plat.shade],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(enabled ? Plat.ink : Plat.shade, lineWidth: 1))
            .padding(isDefault ? 4 : 0)
            .overlay(
                Group {
                    if isDefault {
                        RoundedRectangle(cornerRadius: 7).stroke(enabled ? Plat.ink : Plat.shade, lineWidth: 2.5).padding(1)
                    }
                }
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Checkbox

struct PlatinumCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                ZStack {
                    Rectangle().fill(Plat.well)
                    Bevel(raised: false)
                    Rectangle().strokeBorder(Plat.ink, lineWidth: 1).padding(1)
                    if configuration.isOn {
                        Path { p in
                            p.move(to: CGPoint(x: 3.5, y: 3.5)); p.addLine(to: CGPoint(x: 10.5, y: 10.5))
                            p.move(to: CGPoint(x: 10.5, y: 3.5)); p.addLine(to: CGPoint(x: 3.5, y: 10.5))
                        }.stroke(Plat.ink, lineWidth: 1.5)
                    }
                }
                .frame(width: 14, height: 14)
                configuration.label.font(Plat.font(12)).foregroundStyle(Plat.ink)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slider

/// Platinum slider: sunken groove with a pentagon "house" thumb pointing down.
struct PlatinumSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var defaultValue: Float = 0
    var format: (Float) -> String

    @StateObject private var drag = Flag()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(Plat.font(12)).foregroundStyle(Plat.ink)
                Spacer()
                Text(format(value)).font(Plat.font(11)).foregroundStyle(Plat.dark).monospacedDigit()
            }
            GeometryReader { g in
                let w = g.size.width, thumbW: CGFloat = 11
                let t = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                let x = thumbW / 2 + t * (w - thumbW)
                ZStack(alignment: .topLeading) {
                    // groove
                    Rectangle().fill(Plat.mid)
                        .overlay(Bevel(raised: false))
                        .overlay(Rectangle().strokeBorder(Plat.ink.opacity(0.7), lineWidth: 1).padding(1))
                        .frame(height: 6)
                        .offset(y: 4)
                    // ticks
                    ForEach(0..<9) { i in
                        Rectangle().fill(Plat.dark)
                            .frame(width: 1, height: i % 4 == 0 ? 5 : 3)
                            .offset(x: thumbW / 2 + CGFloat(i) / 8 * (w - thumbW), y: 15)
                    }
                    Thumb(pressed: drag.on)
                        .frame(width: thumbW, height: 15)
                        .offset(x: x - thumbW / 2, y: 0)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { d in
                            drag.on = true
                            let tt = min(max((d.location.x - thumbW / 2) / (w - thumbW), 0), 1)
                            value = range.lowerBound + Float(tt) * (range.upperBound - range.lowerBound)
                        }
                        .onEnded { _ in drag.on = false }
                )
                .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
            }
            .frame(height: 20)
        }
        .help("Double-click to reset")
    }

    struct Thumb: View {
        var pressed: Bool
        var body: some View {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let shape = Path { p in
                    p.move(to: CGPoint(x: 0.5, y: 0.5)); p.addLine(to: CGPoint(x: w - 0.5, y: 0.5))
                    p.addLine(to: CGPoint(x: w - 0.5, y: h * 0.62)); p.addLine(to: CGPoint(x: w / 2, y: h - 0.5))
                    p.addLine(to: CGPoint(x: 0.5, y: h * 0.62)); p.closeSubpath()
                }
                ZStack {
                    shape.fill(pressed ? Plat.accent : Plat.face)
                    shape.stroke(Plat.ink, lineWidth: 1)
                    Path { p in
                        p.move(to: CGPoint(x: 2, y: h * 0.58)); p.addLine(to: CGPoint(x: 2, y: 2)); p.addLine(to: CGPoint(x: w - 2, y: 2))
                    }.stroke(pressed ? Plat.highlight : Plat.light, lineWidth: 1)
                    ForEach(0..<3) { i in
                        Rectangle().fill(Plat.dark).frame(width: w - 5, height: 1).offset(y: CGFloat(i) * 2 - 3)
                    }
                }
            }
        }
    }
}

// MARK: - Popup menu

struct PlatinumPopup<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(Plat.font(12)).foregroundStyle(Plat.ink)
            Menu {
                ForEach(options, id: \.0) { opt in
                    Button(opt.1) { selection = opt.0 }
                }
            } label: {
                HStack(spacing: 0) {
                    Text(options.first { $0.0 == selection }?.1 ?? "")
                        .font(Plat.font(12)).foregroundStyle(Plat.ink)
                        .padding(.leading, 7)
                    Spacer(minLength: 6)
                    ZStack {
                        Rectangle().fill(Plat.face)
                        VStack(spacing: 2) {
                            Triangle(up: true).fill(Plat.ink).frame(width: 7, height: 4)
                            Triangle(up: false).fill(Plat.ink).frame(width: 7, height: 4)
                        }
                    }
                    .frame(width: 18)
                    .overlay(Rectangle().fill(Plat.ink).frame(width: 1), alignment: .leading)
                }
                .frame(height: 20)
                .background(Plat.face)
                .overlay(Bevel(raised: true).padding(1))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Plat.ink, lineWidth: 1))
                .background(RoundedRectangle(cornerRadius: 3).fill(Plat.dark).offset(x: 1, y: 1))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }
}

struct Triangle: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        Path { p in
            if up { p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)) }
            else { p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)) }
            p.closeSubpath()
        }
    }
}

// MARK: - Group box

struct PlatinumGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.top, 14).padding(.horizontal, 8).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                ZStack {
                    Rectangle().stroke(Plat.light, lineWidth: 1).offset(x: 1, y: 1)
                    Rectangle().stroke(Plat.shade, lineWidth: 1)
                }
                .padding(.top, 6)
                .allowsHitTesting(false)
            )
            .overlay(alignment: .topLeading) {
                Text(title).font(Plat.font(11, bold: true)).foregroundStyle(Plat.ink)
                    .padding(.horizontal, 4).background(Plat.face)
                    .offset(x: 8, y: -1)
            }
    }
}

// MARK: - Progress bar

struct PlatinumProgress: View {
    /// nil = indeterminate (barber pole)
    var value: Double?
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Plat.mid)
                if let v = value {
                    Rectangle().fill(Plat.accent)
                        .overlay(Rectangle().fill(Plat.highlight.opacity(0.8)).frame(height: 2), alignment: .top)
                        .frame(width: max(0, g.size.width * CGFloat(min(max(v, 0), 1))))
                } else {
                    TimelineView(.animation) { tl in
                        let phase = CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)) * 16
                        Canvas { ctx, size in
                            var x = -size.height * 2 + phase
                            while x < size.width + size.height {
                                var p = Path()
                                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                                p.addLine(to: CGPoint(x: x + size.height + 8, y: 0)); p.addLine(to: CGPoint(x: x + 8, y: size.height))
                                ctx.fill(p, with: .color(Plat.accent))
                                x += 16
                            }
                        }
                    }
                    .background(Plat.highlight)
                }
            }
            .clipped()
            .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
            .overlay(Bevel(raised: false).padding(-1))
        }
        .frame(height: 12)
    }
}

// MARK: - Window chrome

/// Pinstriped title bar with close / collapse / zoom boxes. Drags the window.
struct PlatinumTitleBar: View {
    let title: String

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
                WindowBox(kind: .close).padding(.leading, 9)
                Spacer()
                WindowBox(kind: .zoom)
                WindowBox(kind: .collapse).padding(.trailing, 9)
            }
            Text(title)
                .font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink)
                .padding(.horizontal, 8)
                .background(Plat.face)
        }
        .frame(height: 22)
        .overlay(Rectangle().fill(Plat.ink).frame(height: 1), alignment: .bottom)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .onTapGesture(count: 2) { Retro.shared.toggleShade() }
    }

    struct WindowBox: View {
        enum Kind { case close, zoom, collapse }
        let kind: Kind
        @StateObject private var press = Flag()
        var body: some View {
            ZStack {
                Rectangle().fill(press.on ? Plat.dark : Plat.face)
                Bevel(raised: !press.on).padding(1)
                Rectangle().strokeBorder(Plat.ink, lineWidth: 1)
                switch kind {
                case .close: EmptyView()
                case .zoom: Rectangle().strokeBorder(Plat.ink, lineWidth: 1).frame(width: 7, height: 7).offset(x: -1, y: -1)
                case .collapse: Rectangle().fill(Plat.ink).frame(width: 9, height: 1).offset(y: -1)
                }
            }
            .frame(width: 13, height: 13)
            .background(Plat.face.padding(-3))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press.on = true }
                    .onEnded { _ in
                        press.on = false
                        guard let w = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                        switch kind {
                        case .close: w.performClose(nil)
                        case .zoom: w.zoom(nil)
                        case .collapse: _ = w; Retro.shared.toggleShade()
                        }
                    }
            )
        }
    }
}

/// Hides the modern title bar so the platinum chrome can take over.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                w.standardWindowButton(b)?.isHidden = true
            }
            // Hide the system title bar container entirely so the platinum one shows through.
            if let container = w.standardWindowButton(.closeButton)?.superview?.superview {
                container.isHidden = true
            }
            w.backgroundColor = NSColor(white: 0.867, alpha: 1)
            w.isMovableByWindowBackground = false
            w.acceptsMouseMovedEvents = true   // idle detection for the Darkroom Saver
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Classic diagonal resize grip (decorative — the window edge does the resizing).
struct ResizeGrip: View {
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<3 {
                let o = CGFloat(i) * 4 + 3
                var p = Path(); p.move(to: CGPoint(x: size.width - o, y: size.height - 1)); p.addLine(to: CGPoint(x: size.width - 1, y: size.height - o))
                ctx.stroke(p, with: .color(Plat.shade), lineWidth: 1)
                var q = Path(); q.move(to: CGPoint(x: size.width - o + 1, y: size.height - 1)); q.addLine(to: CGPoint(x: size.width - 1, y: size.height - o + 1))
                ctx.stroke(q, with: .color(Plat.light), lineWidth: 1)
            }
        }
        .frame(width: 15, height: 15)
    }
}

// MARK: - Film canister icon

struct FilmCanister: View {
    let maker: String
    let kind: FilmStockKindLike
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bodyRect = CGRect(x: w * 0.12, y: h * 0.16, width: w * 0.5, height: h * 0.68)
            let colors = palette
            // film leader
            var leader = Path()
            leader.move(to: CGPoint(x: bodyRect.maxX - 1, y: h * 0.3))
            leader.addLine(to: CGPoint(x: w * 0.95, y: h * 0.3))
            leader.addLine(to: CGPoint(x: w * 0.95, y: h * 0.55))
            leader.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.72), control: CGPoint(x: w * 0.92, y: h * 0.72))
            leader.addLine(to: CGPoint(x: bodyRect.maxX - 1, y: h * 0.72))
            leader.closeSubpath()
            ctx.fill(leader, with: .color(Color(red: 0.42, green: 0.25, blue: 0.12)))
            ctx.stroke(leader, with: .color(.black), lineWidth: 0.8)
            for i in 0..<3 {
                let r = CGRect(x: bodyRect.maxX + 2 + CGFloat(i) * w * 0.1, y: h * 0.33, width: w * 0.05, height: h * 0.05)
                ctx.fill(Path(r), with: .color(.black.opacity(0.7)))
            }
            // body
            ctx.fill(Path(roundedRect: bodyRect, cornerRadius: 1.5), with: .color(colors.0))
            ctx.fill(Path(CGRect(x: bodyRect.minX, y: bodyRect.midY - h * 0.08, width: bodyRect.width, height: h * 0.16)), with: .color(colors.1))
            ctx.fill(Path(CGRect(x: bodyRect.minX + 2, y: bodyRect.minY + 2, width: 2, height: bodyRect.height - 4)), with: .color(.white.opacity(0.45)))
            ctx.stroke(Path(roundedRect: bodyRect, cornerRadius: 1.5), with: .color(.black), lineWidth: 0.8)
            // caps
            for y in [bodyRect.minY - h * 0.08, bodyRect.maxY] {
                let cap = CGRect(x: bodyRect.minX - 1, y: y, width: bodyRect.width + 2, height: h * 0.08)
                ctx.fill(Path(roundedRect: cap, cornerRadius: 1), with: .color(Color(white: 0.25)))
                ctx.stroke(Path(roundedRect: cap, cornerRadius: 1), with: .color(.black), lineWidth: 0.6)
            }
            ctx.fill(Path(CGRect(x: bodyRect.midX - w * 0.06, y: bodyRect.minY - h * 0.15, width: w * 0.12, height: h * 0.08)), with: .color(Color(white: 0.3)))
        }
    }

    private var palette: (Color, Color) {
        switch kind {
        case .bw:
            return maker == "Ilford" ? (Color(white: 0.95), Color(white: 0.1)) : (Color(white: 0.2), Color(red: 0.95, green: 0.72, blue: 0.1))
        case .slide, .neg:
            switch maker {
            case "Kodak": return (Color(red: 0.98, green: 0.73, blue: 0.08), kind == .slide ? Color(red: 0.75, green: 0.1, blue: 0.1) : Color(red: 0.85, green: 0.2, blue: 0.1))
            case "Fujifilm": return (Color(red: 0.12, green: 0.55, blue: 0.3), kind == .slide ? Color(red: 0.55, green: 0.2, blue: 0.55) : Color(white: 0.95))
            default: return (Color(red: 0.75, green: 0.12, blue: 0.15), Color(white: 0.1))
            }
        }
    }
}

enum FilmStockKindLike { case neg, slide, bw }

/// Tiny observable flag (avoids the @State macro, which needs Xcode's macro plugins).
final class Flag: ObservableObject { @Published var on = false }
