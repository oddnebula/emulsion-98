// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Emulsion98",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "FilmEngine",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(name: "Emulsion98", dependencies: ["FilmEngine"]),
        .executableTarget(name: "emulsion-cli", dependencies: ["FilmEngine"]),
        // Photos editing extension (Photos ▸ Edit ▸ Extensions ▸ Emulsion 98), packaged by scripts/build_app.sh.
        .executableTarget(
            name: "Emulsion98PhotosExt",
            dependencies: ["FilmEngine"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            // PhotosUI provides the editing-extension context class; it must be loaded even though no
            // Swift code references it directly (the linker would otherwise drop it).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension",
                                           "-Xlinker", "-needed_framework", "-Xlinker", "PhotosUI"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
