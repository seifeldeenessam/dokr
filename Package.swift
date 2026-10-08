// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dokr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Dokr", targets: ["Dokr"]),
        .executable(name: "DokrFolder", targets: ["DokrFolder"]),
    ],
    targets: [
        // Foundation-only model, Dock plist sync, icns encoding (unit tested).
        .target(name: "DokrCore"),
        // AppKit helpers shared by the editor and the folder helper.
        .target(name: "DokrKit", dependencies: ["DokrCore"]),
        // The editor app.
        .executableTarget(name: "Dokr", dependencies: ["DokrCore", "DokrKit"]),
        // The binary inside every generated folder .app: shows the popup grid.
        .executableTarget(name: "DokrFolder", dependencies: ["DokrCore", "DokrKit"]),
        .testTarget(name: "DokrCoreTests", dependencies: ["DokrCore"]),
    ]
)
