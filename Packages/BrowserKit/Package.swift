// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "BrowserKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrowserCore", targets: ["BrowserCore"]),
        .library(name: "BrowserStorage", targets: ["BrowserStorage"]),
        .library(name: "BrowserWebKit", targets: ["BrowserWebKit"]),
        .library(name: "BrowserExtensions", targets: ["BrowserExtensions"])
    ],
    targets: [
        .target(name: "BrowserCore"),
        .target(name: "BrowserStorage", dependencies: ["BrowserCore"]),
        .target(name: "BrowserWebKit", dependencies: ["BrowserCore"]),
        .target(name: "BrowserExtensions", dependencies: ["BrowserCore"], resources: [.copy("Compatibility/Resources")]),
        .testTarget(name: "BrowserCoreTests", dependencies: ["BrowserCore"]),
        .testTarget(name: "BrowserStorageTests", dependencies: ["BrowserStorage", "BrowserCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "BrowserWebKitTests", dependencies: ["BrowserWebKit", "BrowserCore"]),
        .testTarget(name: "BrowserExtensionsTests", dependencies: ["BrowserExtensions", "BrowserCore"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
