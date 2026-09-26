// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "BrowserKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrowserCore", targets: ["BrowserCore"]),
        .library(name: "BrowserStorage", targets: ["BrowserStorage"]),
        .library(name: "BrowserWebKit", targets: ["BrowserWebKit"])
    ],
    targets: [
        .target(name: "BrowserCore"),
        .target(name: "BrowserStorage", dependencies: ["BrowserCore"]),
        .target(name: "BrowserWebKit", dependencies: ["BrowserCore"]),
        .testTarget(name: "BrowserCoreTests", dependencies: ["BrowserCore"]),
        .testTarget(name: "BrowserStorageTests", dependencies: ["BrowserStorage", "BrowserCore"]),
        .testTarget(name: "BrowserWebKitTests", dependencies: ["BrowserWebKit", "BrowserCore"])
    ],
    swiftLanguageModes: [.v6]
)
