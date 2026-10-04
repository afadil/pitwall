// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pitwall",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Pitwall", targets: ["Pitwall"]),
        .executable(name: "pitwall-check", targets: ["pitwall-check"]),
        .library(name: "PitwallCore", targets: ["PitwallCore"]),
    ],
    targets: [
        .target(
            name: "PitwallCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Pitwall",
            dependencies: ["PitwallCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "pitwall-check",
            dependencies: ["PitwallCore"]
        ),
        .testTarget(
            name: "PitwallCoreTests",
            dependencies: ["PitwallCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
