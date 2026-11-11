import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--snapshot") {
            MainActor.assumeIsolated { _ = Snapshot.runIfRequested(library: Library()) }
            exit(0)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct Emulsion98App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var library = Library()
    @StateObject private var retro = Retro.shared

    var body: some Scene {
        WindowGroup("Emulsion 98") {
            MainView()
                .environmentObject(library)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Emulsion 98") { library.showAbout() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Import Photos…") { library.openPanel() }.keyboardShortcut("o")
                Button("Import from Camera Card") { library.importFromCard() }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Import from Photos Library…") { library.showPhotosBrowser = true }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Open Photos") { PhotosBridge.openPhotosApp() }
                Divider()
                Button("Develop Selected Photo") { library.develop(all: false) }.keyboardShortcut("e")
                Button("Develop All Photos") { library.develop(all: true) }.keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Export Film LUTs…") { library.exportLUTs() }
                Button("Get Info") { retro.showInfo = true }.keyboardShortcut("i").disabled(library.selection == nil)
                Divider()
                Button("Remove from Library") { library.removeSelected() }.keyboardShortcut(.delete, modifiers: [.command])
                Button("Show Developed Folder") {
                    try? FileManager.default.createDirectory(at: Library.developedFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Library.developedFolder)
                }
            }
            CommandMenu("Special") {
                Button("Clean Up Library") { library.cleanUp() }
                Button("Restart Darkroom") { retro.restartDarkroom(); library.scheduleRender() }
                Divider()
                Toggle("Safelight", isOn: $retro.safelight)
                Toggle("Sound Effects", isOn: $retro.sounds)
                Toggle("Show Startup Screen", isOn: $retro.showStartup)
                Menu("Desktop Pattern") {
                    ForEach(DesktopPattern.allCases) { p in
                        Toggle(p.label, isOn: Binding(get: { retro.pattern == p }, set: { if $0 { retro.pattern = p } }))
                    }
                }
                Menu("Darkroom Saver") {
                    ForEach([0, 1, 5, 15], id: \.self) { m in
                        Toggle(m == 0 ? "Never" : "After \(m) minute\(m == 1 ? "" : "s")",
                               isOn: Binding(get: { retro.saverMinutes == m }, set: { if $0 { retro.saverMinutes = m } }))
                    }
                    Divider()
                    Button("Start Now") { retro.saverOn = true }
                }
                Divider()
                Button(retro.shaded ? "Unroll Window" : "Roll Up Window (WindowShade)") { retro.toggleShade() }
                    .keyboardShortcut("w", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button(retro.balloons ? "Hide Balloons" : "Show Balloons") { retro.balloons.toggle() }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                Button("Next Photo") { library.step(photo: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous Photo") { library.step(photo: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Next Film") { library.step(stock: 1) }.keyboardShortcut(.downArrow, modifiers: [.command])
                Button("Previous Film") { library.step(stock: -1) }.keyboardShortcut(.upArrow, modifiers: [.command])
                Divider()
                Button("Toggle Split View") { Library.split.on.toggle() }.keyboardShortcut("\\", modifiers: [.command])
            }
            CommandMenu("Film") {
                ForEach(FilmKind.allCases, id: \.self) { kind in
                    Section(kind.rawValue) {
                        ForEach(FilmStockList.stocks(kind)) { s in
                            Button(s.displayName) { library.stockID = s.id }
                        }
                    }
                }
            }
        }
    }
}

import FilmEngine
enum FilmStockList {
    static func stocks(_ k: FilmKind) -> [FilmStock] { FilmStock.catalog.filter { $0.kind == k } }
}
