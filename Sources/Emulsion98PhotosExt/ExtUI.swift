import SwiftUI
import AppKit
import FilmEngine

struct ExtRoot: View {
    @EnvironmentObject var m: ExtModel
    @StateObject private var hold = Flag()

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                GeometryReader { g in
                    ZStack {
                        Plat.photoWell
                        if let img = hold.on ? (m.original ?? m.preview) : m.preview {
                            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                                .padding(8)
                        }
                        if m.busy {
                            PlatinumProgress(value: nil).frame(width: 140)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(14)
                        }
                        if hold.on {
                            Text("ORIGINAL").font(Plat.font(11, bold: true)).foregroundStyle(Plat.ink)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Plat.highlight)
                                .overlay(Rectangle().strokeBorder(Plat.ink))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
                .padding(2).sunkenWell(Plat.photoWell)
                HStack {
                    Text(m.status).font(Plat.font(11)).foregroundStyle(Plat.dark).lineLimit(1)
                    Spacer()
                    Button("Hold to Compare") {}
                        .buttonStyle(PlatinumButtonStyle(minWidth: 0))
                        .simultaneousGesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in hold.on = true }.onEnded { _ in hold.on = false })
                }
            }
            sidebar.frame(width: 280)
        }
        .padding(8)
        .background(Plat.face)
        .environment(\.colorScheme, .light)
    }

    var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                FilmCanister(maker: m.stock.maker, kind: kindLike(m.stock)).frame(width: 30, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Emulsion 98").font(Plat.font(14, bold: true)).foregroundStyle(Plat.ink)
                    Text(m.stock.displayName).font(Plat.font(11)).foregroundStyle(Plat.dark)
                }
                Spacer()
            }
            PlatinumGroup(title: "Film Stocks") {
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        tab("All", nil); tab("Color", .colorNegative); tab("Slide", .slide); tab("B&W", .blackWhite)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(m.visibleStocks) { s in
                                HStack(spacing: 8) {
                                    FilmCanister(maker: s.maker, kind: kindLike(s)).frame(width: 20, height: 24)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(s.name).font(Plat.font(12, bold: true)).foregroundStyle(Plat.ink)
                                        Text("\(s.maker) · ISO \(s.iso)").font(Plat.font(10)).foregroundStyle(Plat.dark)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(s.id == m.stockID ? Plat.highlight : Color.white)
                                .overlay(Rectangle().fill(Plat.mid).frame(height: 1), alignment: .bottom)
                                .contentShape(Rectangle())
                                .onTapGesture { m.stockID = s.id }
                            }
                        }
                    }
                    .padding(2).sunkenWell(.white)
                }
            }
            PlatinumGroup(title: "Darkroom") {
                ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    PlatinumSlider(title: "Exposure", value: $m.settings.exposure, range: -3...3, defaultValue: 0) {
                        abs($0) < 0.05 ? "Normal" : String(format: "%+.1f stops", $0)
                    }
                    PlatinumSlider(title: "Push / pull", value: $m.settings.push, range: -1...3, defaultValue: 0) {
                        abs($0) < 0.05 ? "Box speed" : String(format: "%+.1f", $0)
                    }
                    PlatinumSlider(title: "Grain", value: $m.settings.grain, range: 0...2, defaultValue: 1) { String(format: "%.0f%%", $0 * 100) }
                    PlatinumSlider(title: "Halation", value: $m.settings.halation, range: 0...3, defaultValue: 1) { String(format: "%.0f%%", $0 * 100) }
                    if m.stock.kind == .colorNegative {
                        PlatinumPopup(title: "Lab:", selection: $m.settings.lab, options: LabProcess.allCases.map { ($0, $0.label) })
                    }
                    PlatinumPopup(title: "Filter:", selection: $m.settings.filter,
                                  options: LensFilter.allCases.filter { $0 == .none || $0 == m.settings.filter || $0.isForBW == (m.stock.kind == .blackWhite) }.map { ($0, $0.label) })
                    if m.stock.crossProcessed != nil {
                        Toggle("Cross-process in C-41", isOn: $m.settings.crossProcess).toggleStyle(PlatinumCheckboxStyle())
                    }
                    if m.stock.kind == .colorNegative {
                        Toggle("Redscale", isOn: $m.settings.redscale).toggleStyle(PlatinumCheckboxStyle())
                    }
                    if m.stock.kind == .blackWhite {
                        PlatinumSlider(title: "Paper grade", value: $m.settings.paperGrade, range: -1...5, defaultValue: 2) {
                            "Grade " + Multigrade.label(($0 * 2).rounded() / 2)
                        }
                    }
                    if m.stock.kind != .slide {
                        PlatinumSlider(title: "Print exposure", value: $m.settings.printExposure, range: -1...1, defaultValue: 0) {
                            abs($0) < 0.02 ? "Auto" : String(format: "%+.2f stops", $0)
                        }
                        PlatinumSlider(title: "Pre-flash", value: $m.settings.preflash, range: 0...1, defaultValue: 0) {
                            $0 < 0.01 ? "Off" : String(format: "%.0f%%", $0 * 100)
                        }
                        if m.stock.kind == .blackWhite {
                            PlatinumPopup(title: "Image tone:", selection: $m.settings.paperTone, options: PaperTone.allCases.map { ($0, $0.label) })
                            PlatinumPopup(title: "Toner:", selection: $m.settings.toner, options: Toner.allCases.map { ($0, $0.label) })
                            if m.settings.toner != .none {
                                PlatinumSlider(title: m.settings.toner == .sepia ? "Bleach" : "Toning time", value: $m.settings.tonerStrength,
                                               range: 0...1, defaultValue: 0.6) { String(format: "%.0f%%", $0 * 100) }
                            }
                            PlatinumPopup(title: "Enlarger:", selection: $m.settings.enlarger, options: Enlarger.allCases.map { ($0, $0.label) })
                        }
                        if m.settings.lab == .print || m.stock.kind == .blackWhite {
                            Toggle("Enlarger lens falloff", isOn: $m.settings.enlargerFalloff).toggleStyle(PlatinumCheckboxStyle())
                        }
                    }
                    PlatinumPopup(title: "Agitation:", selection: $m.settings.agitation, options: Agitation.allCases.map { ($0, $0.label) })
                    PlatinumSlider(title: "Film age", value: $m.settings.ageYears, range: 0...30, defaultValue: 0) {
                        $0 < 0.5 ? "Fresh" : String(format: "%.0f years expired", $0)
                    }
                    if m.settings.ageYears >= 0.5 {
                        PlatinumPopup(title: "Stored:", selection: $m.settings.storage, options: Storage.allCases.map { ($0, $0.label) })
                    }
                    PlatinumSlider(title: Keeping.ageTitle(m.stock, scan: m.settings.lab == .scan), value: $m.settings.printAge,
                                   range: 0...80, defaultValue: 0) {
                        $0 < 0.5 ? "Just developed" : String(format: "%.0f years old", $0)
                    }
                    if m.settings.printAge >= 0.5 {
                        PlatinumPopup(title: "Kept:", selection: $m.settings.keeping, options: Keeping.allCases.map { ($0, $0.label) })
                    }
                    PlatinumPopup(title: "Format:", selection: $m.settings.format, options: FilmFormat.allCases.map { ($0, $0.label) })
                }
                }
                .frame(maxHeight: 330)
            }
            Text("Click Done in Photos to develop at full resolution. Revert to Original undoes it.")
                .font(Plat.font(10)).foregroundStyle(Plat.dark).fixedSize(horizontal: false, vertical: true)
        }
    }

    func tab(_ title: String, _ kind: FilmKind?) -> some View {
        let on = m.kindFilter == kind
        return Button { m.kindFilter = kind } label: {
            Text(title).font(Plat.font(11, bold: on)).foregroundStyle(Plat.ink)
                .frame(maxWidth: .infinity, minHeight: 20)
                .background(on ? Plat.well : Plat.mid)
                .overlay(Bevel(raised: !on))
                .overlay(Rectangle().strokeBorder(Plat.ink, lineWidth: 1).padding(.trailing, -1))
        }
        .buttonStyle(.plain)
    }

    func kindLike(_ s: FilmStock) -> FilmStockKindLike { s.kind == .blackWhite ? .bw : (s.kind == .slide ? .slide : .neg) }
}
