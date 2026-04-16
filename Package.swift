// swift-tools-version: 5.10
import PackageDescription

// NOTE on Sparkle:
// Sparkle is NOT declared here. The real app is built by Makefile with swiftc
// directly, which passes `-F Vendor/Sparkle/Sparkle.xcframework/...` to the
// compiler. Any Sparkle code in Sources/ is guarded with `#if canImport(Sparkle)`,
// so `swift test` (which uses this Package.swift) skips Sparkle entirely —
// avoiding Library Validation errors when loading a Sparkle-signed framework
// into Xcode's test bundle.
let package = Package(
    name: "aimeter",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "aimeter", targets: ["AIMeter"]),
    ],
    targets: [
        .executableTarget(
            name: "AIMeter",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "AIMeterTests",
            dependencies: ["AIMeter"],
            path: "Tests/AIMeterTests"
        ),
    ]
)
