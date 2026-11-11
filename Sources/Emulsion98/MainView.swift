import SwiftUI
import AppKit
import FilmEngine

struct MainView: View {
    @EnvironmentObject var lib: Library
    @ObservedObject var retro = Retro.shared

    var body: some View {
        VStack(spacing: 0) {
            PlatinumTitleBar(title: "Emulsion 98").zIndex(1)
                .balloon("Title bar. Drag to move the window. Double-click it, or click the box at the far right, to roll the window up like a window shade.")
            if !retro.shaded {
                Toolbar()
                HStack(alignment: .top, spacing: 8) {
                    StockList().frame(width: 262)
                    VStack(spacing: 8) {
                        PreviewPane()
                        Filmstrip().frame(height: 104)
                    }
                    Inspector().frame(width: 262)
                }
                .padding(8)
                StatusBar()
            }
        }
        .frame(minWidth: 1180, minHeight: retro.shaded ? 22 : 760, maxHeight: retro.shaded ? 22 : .infinity, alignment: .top)
        .background(Plat.face)
        .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1).allowsHitTesting(false))
        .overlay { if lib.showPhotosBrowser { PhotosBrowser() } }
        .overlay { DialogLayer() }
        .overlay { AboutBox() }
        .overlay { GetInfoBox() }
        .overlay { if !retro.shaded { StartupScreen() } }
        .overlay { BalloonLayer() }
        .overlay { DarkroomSaver() }
        .onAppear { IdleWatcher.shared.start() }
        .colorMultiply(retro.safelight ? Color(red: 1, green: 0.32, blue: 0.25) : .white)
        .coordinateSpace(.named("window"))
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .dropDestination(for: URL.self) { urls, _ in lib.add(urls); return true }
        .environment(\.colorScheme, .light)
        .toolbar(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: - Toolbar

struct Toolbar: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        HStack(spacing: 8) {
            Button("Import Photos…") { lib.openPanel() }.buttonStyle(PlatinumButtonStyle())
                .balloon("Import Photos. Adds photos or whole folders from your disk. RAW files give the film the most to work with.")
            Button("Import from Card") { lib.importFromCard() }.buttonStyle(PlatinumButtonStyle())
                .balloon("Import from Card. Copies new photos from your camera's SD card into Pictures ▸ Emulsion 98.")
            Button("Photos Library…") { lib.showPhotosBrowser = true }.buttonStyle(PlatinumButtonStyle())
                .balloon("Photos Library. Browse the Photos app and bring pictures into the darkroom.")
            Toggle("Watch for camera cards", isOn: $lib.watchCards).toggleStyle(PlatinumCheckboxStyle())
                .padding(.leading, 4)
                .balloon("When this is checked, Emulsion 98 offers to import whenever you insert a camera card.")
            Spacer()
            Button("Develop Selected") { lib.develop(all: false) }
                .buttonStyle(PlatinumButtonStyle())
                .disabled(lib.selection == nil || lib.busy)
                .balloon("Develop Selected. Develops the photo you are looking at, at full resolution, in the chosen film.")
            Button("Develop All") { lib.develop(all: true) }
                .buttonStyle(PlatinumButtonStyle(isDefault: true))
                .disabled(lib.photos.isEmpty || lib.busy)
                .balloon("Develop All. Develops every photo on the filmstrip. Go make a coffee; the darkroom will chime when it's done.")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .raisedPanel()
    }
}

// MARK: - Stock list

struct StockList: View {
    @EnvironmentObject var lib: Library

    var body: some View {
        PlatinumGroup(title: "Film Stocks") {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    tab("All", nil)
                    tab("Color", .colorNegative)
                    tab("Slide", .slide)
                    tab("B&W", .blackWhite)
                }
                ScrollViewReader { proxy in
                    MaybeScroll(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(lib.visibleStocks) { s in
                                StockRow(stock: s, selected: s.id == lib.stockID, thumb: lib.stockThumbs[s.id])
                                    .id(s.id)
                                    .onTapGesture { lib.stockID = s.id }
                                    .balloon("\(s.displayName). \(s.blurb) Click to load this film.")
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .padding(2)
                    .sunkenWell(.white)
                    .onAppear { proxy.scrollTo(lib.stockID, anchor: .center) }
                }
            }
        }
    }

    func tab(_ title: String, _ kind: FilmKind?) -> some View {
        let on = lib.kindFilter == kind
        return Button { lib.kindFilter = kind } label: {
            Text(title).font(Plat.font(11, bold: on)).foregroundStyle(Plat.ink)
                .frame(maxWidth: .infinity, minHeight: 20)
                .background(on ? Plat.well : Plat.mid)
                .overlay(Bevel(raised: !on))
                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1).padding(.trailing, -1))
        }
        .buttonStyle(.plain)
    }
}

struct StockRow: View {
    let stock: FilmStock
    let selected: Bool
    let thumb: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            FilmCanister(maker: stock.maker, kind: stock.kind == .blackWhite ? .bw : (stock.kind == .slide ? .slide : .neg))
                .frame(width: 26, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(stock.name).font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink).lineLimit(1)
                Text("\(stock.maker) · ISO \(stock.iso)").font(Plat.font(10)).foregroundStyle(Plat.dark).lineLimit(1)
                Text(stock.kind.rawValue).font(Plat.font(10)).foregroundStyle(Plat.dark).lineLimit(1)
            }
            Spacer(minLength: 2)
            ZStack {
                Rectangle().fill(Plat.photoWell)
                if let t = thumb {
                    Image(nsImage: t).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 62, height: 44).clipped()
            .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(selected ? Plat.highlight : Color.white)
        .overlay(Rectangle().fill(Plat.mid).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

struct PreviewPane: View {
    @EnvironmentObject var lib: Library
    @StateObject private var hold = Flag()
    @ObservedObject var split = Library.split

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                ZStack {
                    PatternFill(pattern: Retro.shared.pattern)
                    if let err = lib.renderError, lib.preview == nil {
                        SadCameraView(message: err)
                    } else if let img = (hold.on ? lib.original : lib.preview) ?? lib.preview {
                        let fit = fitted(img.size, in: g.size)
                        Image(nsImage: img).resizable().interpolation(.high)
                            .frame(width: fit.width, height: fit.height)
                            .overlay {
                                if split.on, !hold.on, let o = lib.original { SplitOverlay(original: o, size: fit, split: split) }
                            }
                            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1))
                            .overlay(alignment: .topLeading) {
                                if let p = lib.loupePoint {
                                    Rectangle().strokeBorder(Color.white, lineWidth: 1)
                                        .background(Rectangle().strokeBorder(Color.black, lineWidth: 3))
                                        .frame(width: loupeBox(img).width * fit.width, height: loupeBox(img).height * fit.height)
                                        .offset(x: p.x * fit.width - loupeBox(img).width * fit.width / 2,
                                                y: p.y * fit.height - loupeBox(img).height * fit.height / 2)
                                        .allowsHitTesting(false)
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                    .onEnded { v in
                                        lib.inspect(at: CGPoint(x: min(max(v.location.x / fit.width, 0), 1),
                                                                y: min(max(v.location.y / fit.height, 0), 1)))
                                    }
                            )
                    } else if lib.selection != nil {
                        VStack(spacing: 8) {
                            Text("Developing…").font(Plat.font(12)).foregroundStyle(.white)
                            PlatinumProgress(value: nil).frame(width: 160)
                        }
                    } else {
                        EmptyState()
                    }
                    if hold.on {
                        Text("ORIGINAL").font(Plat.font(11, bold: true)).foregroundStyle(Plat.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Plat.highlight)
                            .overlay(Rectangle().strokeBorder(Plat.ink))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                    }
                }
            }
            .padding(2)
            .sunkenWell(Plat.photoWell)
            .balloon("The developed photo. Click anywhere on it to look at the grain at 1:1 in the Grain Loupe.")

            HStack(spacing: 8) {
                Text(lib.selection?.lastPathComponent ?? "No photo selected")
                    .font(Plat.font(11)).foregroundStyle(Plat.dark).lineLimit(1)
                if lib.rendering { Text("· developing").font(Plat.font(11)).foregroundStyle(Plat.accent) }
                Spacer()
                Text("Click the photo to inspect grain at 1:1").font(Plat.font(10)).foregroundStyle(Plat.dark)
                Toggle("Split", isOn: $split.on).toggleStyle(PlatinumCheckboxStyle())
                    .disabled(lib.original == nil)
                    .balloon("Split view. Shows the original and the film side by side with a divider you can drag.")
                Button("Hold to Compare") {}
                    .buttonStyle(PlatinumButtonStyle(minWidth: 0))
                    .simultaneousGesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in hold.on = true }
                        .onEnded { _ in hold.on = false })
                    .disabled(lib.preview == nil)
                    .balloon("Hold this button down to see the original digital photo. Let go to see the film.")
            }
            .padding(.top, 6)
        }
    }

    func fitted(_ s: CGSize, in box: CGSize) -> CGSize {
        let k = min((box.width - 16) / max(s.width, 1), (box.height - 16) / max(s.height, 1))
        return CGSize(width: s.width * k, height: s.height * k)
    }

    /// Fraction of the frame covered by the 1:1 loupe (240 px at full resolution).
    func loupeBox(_ img: NSImage) -> CGSize {
        // preview is ≤1600 px; full res unknown here, assume LX5-class 3648 px if preview is capped.
        let previewLong = max(img.size.width, img.size.height)
        let fullLong = previewLong >= CGFloat(RenderService.previewLong) - 1 ? 3648 : previewLong
        return CGSize(width: 240 / (fullLong * img.size.width / previewLong), height: 240 / (fullLong * img.size.height / previewLong))
    }
}

struct EmptyState: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        VStack(spacing: 12) {
            FilmCanister(maker: "Kodak", kind: .neg).frame(width: 70, height: 80)
            Text("No photos loaded").font(Plat.font(14, bold: true)).foregroundStyle(.white)
            Text("Drag photos or folders here, import from your camera card,\nor choose File ▸ Import Photos…")
                .font(Plat.font(12)).foregroundStyle(Color(white: 0.8)).multilineTextAlignment(.center)
            Button("Import Photos…") { lib.openPanel() }.buttonStyle(PlatinumButtonStyle(isDefault: true))
        }
    }
}

// MARK: - Filmstrip

struct Filmstrip: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.11, blue: 0.07)
            // sprocket holes
            Canvas { ctx, size in
                for x in stride(from: 6.0, to: size.width, by: 14) {
                    for y in [4.0, size.height - 10] {
                        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: 7, height: 6), cornerRadius: 1), with: .color(Color(white: 0.85)))
                    }
                }
            }
            MaybeScroll(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(lib.photos) { p in
                        let sel = p.url == lib.selection
                        VStack(spacing: 2) {
                            ZStack {
                                Color.black
                                if let t = lib.photoThumbs[p.url] {
                                    Image(nsImage: t).resizable().aspectRatio(contentMode: .fit)
                                }
                            }
                            .frame(width: 92, height: 62)
                            .overlay(Rectangle().strokeBorder(sel ? Plat.highlight : Color.clear, lineWidth: 3))
                            Text(p.name).font(Plat.font(9)).foregroundStyle(Color(red: 1, green: 0.75, blue: 0.35)).lineLimit(1)
                                .frame(width: 92)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { lib.selection = p.url }
                        .contextMenu {
                            Button("Remove from Library") { lib.selection = p.url; lib.removeSelected() }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([p.url]) }
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 14)
            }
            .scrollIndicators(.never)
        }
        .padding(2)
        .sunkenWell(.black)
        .balloon("The filmstrip. Click a frame to work on it. Control-click for more choices.")
    }
}

// MARK: - Inspector

struct Inspector: View {
    @EnvironmentObject var lib: Library
    var scrolls = true
    var body: some View {
        // Scrolls when the window is too short for every control (classic scrolling panel).
        if scrolls {
            MaybeScroll(.vertical) { content.padding(.trailing, 1) }.scrollIndicators(.automatic)
        } else { content }
    }

    var content: some View {
        VStack(spacing: 8) {
            CameraPanel()
            PlatinumGroup(title: "Film") {
                let s = lib.stock
                VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    FilmCanister(maker: s.maker, kind: s.kind == .blackWhite ? .bw : (s.kind == .slide ? .slide : .neg))
                        .frame(width: 40, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.displayName).font(Plat.font(13, bold: true)).foregroundStyle(Plat.ink)
                        Text("ISO \(s.iso) · \(s.kind.rawValue)").font(Plat.font(11)).foregroundStyle(Plat.dark)
                    }
                }
                Text(s.blurb).font(Plat.font(10)).foregroundStyle(Plat.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
                }
            }

            PlatinumGroup(title: "Darkroom") {
                VStack(alignment: .leading, spacing: 6) {
                    PlatinumSlider(title: "Exposure", value: $lib.settings.exposure, range: -3...3, defaultValue: 0) {
                        abs($0) < 0.05 ? "Normal" : String(format: "%+.1f stops", $0)
                    }
                    .balloon("Exposure. Over- or under-expose the film. The lab still prints it normally, so you see the film's real latitude: negatives forgive overexposure, slides don't.")
                    PlatinumSlider(title: "Push / pull process", value: $lib.settings.push, range: -1...3, defaultValue: 0) {
                        abs($0) < 0.05 ? "Box speed" : String(format: "%@%.1f · EI %d", $0 > 0 ? "Push +" : "Pull ", abs($0),
                                                               Int((Float(lib.stock.iso) * pow(2, $0)).rounded()))
                    }
                    .balloon("Push / pull. Rate the film faster and develop longer: more contrast, more grain and the colour crossovers of a pushed negative.")
                    PlatinumSlider(title: "Grain", value: $lib.settings.grain, range: 0...2, defaultValue: 1) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                    .balloon("Grain. 100% matches the film's datasheet granularity. Double-click the slider to reset it.")
                    PlatinumSlider(title: "Halation", value: $lib.settings.halation, range: 0...3, defaultValue: 1) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                    .balloon("Halation. The red glow around bright lights, from light bouncing off the film base.")
                    if lib.stock.kind != .blackWhite {
                        PlatinumSlider(title: "Lab colour correction", value: $lib.settings.labCorrection, range: 0...1, defaultValue: 0.7) {
                            String(format: "%.0f%%", $0 * 100)
                        }
                        .disabled(!lib.settings.sceneLight)
                        .opacity(lib.settings.sceneLight ? 1 : 0.5)
                    }
                    if lib.stock.kind == .colorNegative {
                        PlatinumPopup(title: "Lab:", selection: $lib.settings.lab,
                                      options: LabProcess.allCases.map { ($0, $0.label) })
                            .balloon("Lab. Optical print: the negative printed on colour paper, rich and contrasty. Lab scan: a minilab scanner reads the negative with RGB light and inverts it — flatter, open shadows, soft highlights.")
                    }
                    PlatinumPopup(title: "Filter:", selection: $lib.settings.filter,
                                  options: LensFilter.allCases.filter { $0 == .none || $0 == lib.settings.filter || $0.isForBW == (lib.stock.kind == .blackWhite) }
                                    .map { ($0, $0.label) })
                        .balloon("Lens filter. Applied to the light's spectrum, with the exposure raised as a through-the-lens meter would: a red filter on B&W darkens blue skies; 85B / 80A convert daylight and tungsten light for colour film.")
                    if lib.stock.crossProcessed != nil {
                        Toggle("Cross-process in C-41", isOn: $lib.settings.crossProcess).toggleStyle(PlatinumCheckboxStyle())
                            .balloon("Cross-processing. The slide film is developed as a negative and printed on negative paper: no orange mask, so contrast soars and colours cross over.")
                    }
                    if lib.stock.kind == .colorNegative {
                        Toggle("Redscale (film loaded backwards)", isOn: $lib.settings.redscale).toggleStyle(PlatinumCheckboxStyle())
                            .balloon("Redscale. Light reaches the layers through the orange base and in reverse order: the blue layer barely sees anything, so the picture turns red, orange and yellow.")
                    }
                    PlatinumPopup(title: "Agitation:", selection: $lib.settings.agitation,
                                  options: Agitation.allCases.map { ($0, $0.label) })
                        .balloon("Agitation. Datasheets assume continuous agitation. Hand-tank inversions let the developer exhaust next to dense areas (stronger edges); stand development compensates bright skies and can leave bromide-drag streaks.")
                    PlatinumSlider(title: "Film age", value: $lib.settings.ageYears, range: 0...30, defaultValue: 0) {
                        $0 < 0.5 ? "Fresh" : String(format: "%.0f years expired", $0)
                    }
                    .balloon("Expired film. Each layer loses speed and gains fog as the emulsion ages; cold storage slows it, but background radiation fogs fast film even in a freezer.")
                    if lib.settings.ageYears >= 0.5 {
                        PlatinumPopup(title: "Stored:", selection: $lib.settings.storage,
                                      options: Storage.allCases.map { ($0, $0.label) })
                    }
                    PlatinumSlider(title: Keeping.ageTitle(lib.stock, scan: lib.settings.lab == .scan), value: $lib.settings.printAge,
                                   range: 0...80, defaultValue: 0) {
                        $0 < 0.5 ? "Just developed" : String(format: "%.0f years old", $0)
                    }
                    .balloon("Archival fading. The finished picture ages after processing: each dye fades at its own rate, and unused couplers turn the whites yellow. In the dark, old prints go red and Ektachrome goes magenta; on display, light fades magenta and yellow first and prints turn cyan. Kodachrome barely fades in the dark.")
                    if lib.settings.printAge >= 0.5 {
                        PlatinumPopup(title: "Kept:", selection: $lib.settings.keeping,
                                      options: Keeping.allCases.map { ($0, $0.label) })
                    }
                    if let sel = lib.selection {
                        PlatinumPopup(title: "Double exposure:", selection: lib.secondBinding,
                                      options: [(URL?.none, "None")] + lib.photos.filter { $0.url != sel }.map { (Optional($0.url), $0.name) })
                            .balloon("Multiple exposure. A second photo exposes the same frame of film. Light adds up in each emulsion layer before development, so dark parts of one picture let the other show through and bright parts of either dominate, just as when you cock the shutter twice.")
                        if lib.secondExposure(for: sel) != nil {
                            PlatinumSlider(title: "Second frame", value: $lib.settings.secondEV, range: -2...2, defaultValue: 0) {
                                abs($0) < 0.05 ? "Equal" : String(format: "%+.1f stops", $0)
                            }
                            Toggle("Give each frame −1 stop", isOn: $lib.settings.multiCompensate).toggleStyle(PlatinumCheckboxStyle())
                        }
                    }
                    if !(lib.stock.kind == .colorNegative && lib.settings.lab == .scan) {
                        PlatinumPopup(title: "Viewed under:", selection: $lib.settings.viewing,
                                      options: ViewingLight.options(slide: lib.stock.kind == .slide).map { ($0, $0.label) })
                            .balloon("Viewing light. The print's dyes are lit by this light spectrum, so colours shift against each other (metamerism), and your eye only partly adapts: a print under a living-room lamp stays warm, by candlelight warmer still.")
                    }
                    PlatinumSlider(title: "Dust & hair", value: $lib.settings.dust, range: 0...1, defaultValue: 0) {
                        $0 < 0.01 ? "Clean" : String(format: "%.0f%%", $0 * 100)
                    }
                    .balloon("Dust and hair on the developed film. They block light, so on a print from a negative they come out white; on a slide they are dark. A condenser enlarger shows every speck; a diffusion head softens them.")
                    PlatinumSlider(title: "Scratches", value: $lib.settings.scratches, range: 0...1, defaultValue: 0) {
                        $0 < 0.01 ? "None" : String(format: "%.0f%%", $0 * 100)
                    }
                    .balloon("Scratches along the film. A shallow emulsion scratch removes only the top, yellow-dye layer, so it shows as a coloured line; a deep one reaches the base. Base-side scratches scatter light and show mostly under a condenser.")
                    PlatinumSlider(title: "Light leak", value: $lib.settings.lightLeak, range: 0...1, defaultValue: 0) {
                        $0 < 0.01 ? "None" : String(format: "%.0f%%", $0 * 100)
                    }
                    .balloon("Light leak. Light gets in through the camera back, crosses the film base and reaches the red-sensitive layer first, which is why leaks glow red and orange.")
                    PlatinumPopup(title: "Format:", selection: $lib.settings.format,
                                  options: FilmFormat.allCases.map { ($0, $0.label) })
                    PlatinumPopup(title: "Border:", selection: $lib.settings.border,
                                  options: FilmBorder.allCases.map { ($0, $0.label) })
                        .balloon("Film border, added when you develop: the rough black edge of a filed negative carrier on a white paper margin, or a full-frame scan of the strip with sprocket holes and edge printing.")
                    PlatinumPopup(title: "Save as:", selection: $lib.exportFormat,
                                  options: ExportFormat.allCases.map { ($0, $0.label) })
                    PlatinumPopup(title: "Send to:", selection: $lib.destination,
                                  options: ExportDestination.allCases.map { ($0, $0.label) })
                    if lib.destination.usesPhotos {
                        Toggle("Apply as edit to Photos original", isOn: $lib.editInPlace)
                            .toggleStyle(PlatinumCheckboxStyle())
                            .help("For photos imported from Photos: the film becomes a non-destructive edit of the original (Revert to Original undoes it). Others go to the “Emulsion 98” album.")
                    }
                }
            }

            if lib.stock.kind != .slide {
                PlatinumGroup(title: "Printing") {
                    VStack(alignment: .leading, spacing: 6) {
                        if lib.stock.kind == .blackWhite {
                            PlatinumSlider(title: "Paper grade", value: $lib.settings.paperGrade, range: -1...5, defaultValue: 2) {
                                "Grade " + Multigrade.label(($0 * 2).rounded() / 2)
                            }
                            .balloon("Variable-contrast paper. Grade 00 is very soft, 5 very hard. The grade filter changes how much blue light reaches the paper's hard, blue-sensitive emulsion versus its soft, green-sensitised one.")
                        }
                        PlatinumSlider(title: "Print exposure", value: $lib.settings.printExposure, range: -1...1, defaultValue: 0) {
                            abs($0) < 0.02 ? "Auto" : String(format: "%+.2f stops", $0)
                        }
                        .balloon("Print exposure. Longer exposure under the enlarger prints darker. Paper is contrasty, so small changes matter.")
                        PlatinumSlider(title: lib.stock.kind == .blackWhite ? "Yellow (softer)" : "Yellow filtration", value: $lib.settings.ccYellow, range: -40...40, defaultValue: 0) {
                            abs($0) < 0.5 ? "0 CC" : String(format: "%+.0f CC", $0)
                        }
                        .balloon(lib.stock.kind == .blackWhite ? "Yellow in the colour head: less blue light, a softer grade." : "Yellow filtration in the enlarger's colour head: more yellow takes blue light away and makes the print bluer.")
                        PlatinumSlider(title: lib.stock.kind == .blackWhite ? "Magenta (harder)" : "Magenta filtration", value: $lib.settings.ccMagenta, range: -40...40, defaultValue: 0) {
                            abs($0) < 0.5 ? "0 CC" : String(format: "%+.0f CC", $0)
                        }
                        .balloon(lib.stock.kind == .blackWhite ? "Magenta in the colour head: less green light, a harder grade." : "Magenta filtration: more magenta takes green light away and makes the print greener.")
                        if lib.settings.lab == .print || lib.stock.kind == .blackWhite {
                            PlatinumPopup(title: "Paper:", selection: $lib.settings.paperSurface,
                                          options: PaperSurface.allCases.map { ($0, $0.label) })
                                .balloon("Paper surface. Glossy prints the deepest blacks; lustre and matte reflect more light off their surface, so blacks are softer.")
                        }
                        PlatinumSlider(title: "Pre-flash", value: $lib.settings.preflash, range: 0...1, defaultValue: 0) {
                            $0 < 0.01 ? "Off" : String(format: "%.0f%%", $0 * 100)
                        }
                        .balloon("Pre-flash. A faint, even exposure of the paper before printing, so the brightest highlight detail of a dense negative prints instead of staying paper-white.")
                        if lib.stock.kind == .blackWhite {
                            PlatinumPopup(title: "Image tone:", selection: $lib.settings.paperTone,
                                          options: PaperTone.allCases.map { ($0, $0.label) })
                                .balloon("Paper image tone. Warm-tone papers develop finer silver, which absorbs more blue light (brown-black, on a cream base); cold-tone papers give a blue-black.")
                            PlatinumPopup(title: "Toner:", selection: $lib.settings.toner,
                                          options: Toner.allCases.map { ($0, $0.label) })
                                .balloon("Toning. Selenium converts the densest silver first: deeper, slightly purple-brown shadows. Sepia bleaches the thinnest silver first and redevelops it as brown silver sulfide; a short bleach browns only the highlights (split tone).")
                            if lib.settings.toner != .none {
                                PlatinumSlider(title: lib.settings.toner == .sepia ? "Bleach" : "Toning time", value: $lib.settings.tonerStrength,
                                               range: 0...1, defaultValue: 0.6) { String(format: "%.0f%%", $0 * 100) }
                            }
                            PlatinumPopup(title: "Enlarger:", selection: $lib.settings.enlarger,
                                          options: Enlarger.allCases.map { ($0, $0.label) })
                                .balloon("Enlarger light. A condenser's focused light is scattered away by the silver grains (the Callier effect), so the negative prints denser where it has more silver: about a grade harder, with crisper grain. A diffusion head is gentler.")
                        }
                        if lib.settings.lab == .print || lib.stock.kind == .blackWhite {
                            Toggle("Enlarger lens falloff", isOn: $lib.settings.enlargerFalloff).toggleStyle(PlatinumCheckboxStyle())
                                .balloon("Light falloff. Less light reaches the paper's corners through the enlarging lens, so corners print slightly lighter — the opposite of camera vignetting. Printers burned them in by hand.")
                        }
                    }
                }
            }

            PlatinumGroup(title: "Grain Loupe · 1:1") {
                ZStack {
                    Plat.photoWell
                    if let l = lib.loupe {
                        Image(nsImage: l).resizable().interpolation(.none)
                    } else {
                        Text(lib.loupePoint == nil ? "Click the photo\nto inspect grain" : "Developing…")
                            .font(Plat.font(11)).foregroundStyle(Color(white: 0.75)).multilineTextAlignment(.center)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(height: 190)
                .padding(2)
                .sunkenWell(Plat.photoWell)
                .balloon("Grain Loupe. Shows a 1:1 crop of the full-resolution develop where you last clicked.")
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Camera

struct CameraPanel: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        PlatinumGroup(title: "Camera") { cameraBody }
            .balloon("Camera. What the photo's metadata says about how it was shot. The film uses the shutter speed and the scene light.")
    }

    var cameraBody: some View {
        Group {
            VStack(alignment: .leading, spacing: 3) {
                if let c = lib.capture {
                    HStack(spacing: 6) {
                        Text(c.cameraName).font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink).lineLimit(1)
                        if c.profileName != "Generic" {
                            Text("PROFILE").font(Plat.font(8, bold: true)).foregroundStyle(Plat.ink)
                                .padding(.horizontal, 3).background(Plat.highlight)
                                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                                .help("Tuned decoding for the \(c.profileName): noise reduction by ISO, no digital sharpening, lens correction, highlight recovery")
                        }
                    }
                    Text(c.exposureSummary.isEmpty ? (c.isRAW ? "RAW" : "No exposure data") : c.exposureSummary)
                        .font(Plat.font(10)).foregroundStyle(Plat.dark).lineLimit(1)
                    Text(lightDescription(c)).font(Plat.font(10)).foregroundStyle(Plat.dark).lineLimit(1)
                } else {
                    Text(lib.selection == nil ? "No photo selected" : "Reading…").font(Plat.font(11)).foregroundStyle(Plat.dark)
                }
                Toggle("Reciprocity failure (long exposures)", isOn: $lib.settings.reciprocity)
                    .toggleStyle(PlatinumCheckboxStyle())
                    .help("Uses the shutter speed: beyond each stock's limit film loses speed and shifts colour layer by layer (Tri-X loses ~1 stop at 1 s; Acros and Provia barely change).")
                Toggle("Film sees the real scene light", isOn: $lib.settings.sceneLight)
                    .toggleStyle(PlatinumCheckboxStyle())
                    .help("Uses the RAW's as-shot white balance: daylight film turns warm under tungsten, tungsten film turns blue in daylight — then the lab corrects part of it.")
                    .padding(.top, 2)
            }
        }
    }

    func lightDescription(_ c: CaptureInfo) -> String {
        guard c.isRAW, let k = c.asShotKelvin else { return c.isRAW ? "Scene light: unknown" : "JPEG: scene light not recorded" }
        let kind: String
        switch k {
        case ..<3400: kind = "tungsten"
        case ..<4500: kind = "warm / fluorescent"
        case ..<6000: kind = "daylight"
        case ..<7500: kind = "overcast"
        default: kind = "shade"
        }
        return "Scene light: \(Int(k)) K (\(kind))"
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        HStack(spacing: 10) {
            ControlStrip()
            Text(lib.status).font(Plat.font(11)).foregroundStyle(Plat.ink).lineLimit(1)
            Spacer()
            Text("\(lib.photos.count) photo\(lib.photos.count == 1 ? "" : "s") · \(lib.stock.displayName)")
                .font(Plat.font(11)).foregroundStyle(Plat.dark)
            if lib.busy { PlatinumProgress(value: lib.progress).frame(width: 160) }
            ResizeGrip()
        }
        .padding(.leading, 1).padding(.trailing, 3).padding(.vertical, 1)
        .frame(height: 22)
        .raisedPanel()
    }
}

// MARK: - Dialogs

struct DialogLayer: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        if let d = lib.dialog {
            ZStack {
                Color.black.opacity(0.001).contentShape(Rectangle())
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        DialogIcon(icon: d.icon).frame(width: 40, height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.title).font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink)
                            Text(d.message).font(Plat.font(12)).foregroundStyle(Plat.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 10) {
                        Spacer()
                        ForEach(Array(d.buttons.enumerated()), id: \.offset) { i, b in
                            Button(b.0) { lib.dialog = nil; b.1() }
                                .buttonStyle(PlatinumButtonStyle(isDefault: i == d.defaultIndex, minWidth: 70))
                                .keyboardShortcut(i == d.defaultIndex ? .defaultAction : (b.0 == "Not Now" ? .cancelAction : nil))
                        }
                    }
                }
                .padding(16)
                .frame(width: 400)
                .background(Plat.face)
                .overlay(Bevel(raised: true).padding(3))
                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1))
                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1).padding(4))
                .background(Rectangle().fill(Color.black.opacity(0.6)).offset(x: 3, y: 3))
            }
        }
    }
}

struct DialogIcon: View {
    let icon: RetroDialog.Icon
    var body: some View {
        switch icon {
        case .film: FilmCanister(maker: "Kodak", kind: .neg)
        case .bomb: PixelIcon(rows: Pixels.bomb, scale: 2.5)
        case .note, .caution:
            Canvas { ctx, size in
                let r = CGRect(x: 4, y: 2, width: size.width - 8, height: size.height - 4)
                if icon == .caution {
                    var t = Path(); t.move(to: CGPoint(x: r.midX, y: r.minY)); t.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); t.addLine(to: CGPoint(x: r.minX, y: r.maxY)); t.closeSubpath()
                    ctx.fill(t, with: .color(Color(red: 1, green: 0.85, blue: 0.1))); ctx.stroke(t, with: .color(.black), lineWidth: 1.5)
                    ctx.draw(Text("!").font(.custom("Geneva", size: 22).bold()), at: CGPoint(x: r.midX, y: r.midY + 6))
                } else {
                    ctx.fill(Path(ellipseIn: r.insetBy(dx: 2, dy: 4)), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: r.insetBy(dx: 2, dy: 4)), with: .color(.black), lineWidth: 1.5)
                    ctx.draw(Text("i").font(.custom("Geneva", size: 20).bold()), at: CGPoint(x: r.midX, y: r.midY))
                }
            }
        }
    }
}

/// A scroll view — except when rendering README / snapshot images, where ImageRenderer cannot draw
/// scroll-view contents, so the content is laid out directly and clipped.
struct MaybeScroll<Content: View>: View {
    let axis: Axis.Set
    @ViewBuilder var content: Content
    init(_ axis: Axis.Set, @ViewBuilder content: () -> Content) { self.axis = axis; self.content = content() }
    var body: some View {
        if Snapshot.active {
            GeometryReader { g in
                content.fixedSize(horizontal: axis == .horizontal, vertical: axis == .vertical)
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            }
            .clipped()
        } else {
            ScrollView(axis) { content }
        }
    }
}
