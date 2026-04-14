// swift-tools-version: 5.10
import PackageDescription

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
