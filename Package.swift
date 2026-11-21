// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JavaScriptCore",
    products: [
        // The Swift API.
        .library(name: "JavaScriptCoreSwift", targets: ["JavaScriptCoreSwift"]),
        // The engine's C API alone.
        .library(name: "CJavaScriptCore", targets: ["CJavaScriptCore"]),
    ],
    targets: [
        // The engine itself: WebKit's JSCOnly port as Scripts/build-engine.sh
        // installs it, or the system framework on Apple's platforms.
        .systemLibrary(name: "CJavaScriptCore", pkgConfig: "javascriptcore"),
        .target(name: "JavaScriptCoreSwift", dependencies: ["CJavaScriptCore"]),
        .testTarget(name: "JavaScriptCoreSwiftTests", dependencies: ["JavaScriptCoreSwift"]),
    ]
)
