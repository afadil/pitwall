// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentBoard",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "AgentBoard", targets: ["AgentBoard"]),
        .executable(name: "agentboard-check", targets: ["agentboard-check"]),
        .library(name: "AgentBoardCore", targets: ["AgentBoardCore"]),
    ],
    targets: [
        .target(
            name: "AgentBoardCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "AgentBoard",
            dependencies: ["AgentBoardCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "agentboard-check",
            dependencies: ["AgentBoardCore"]
        ),
        .testTarget(
            name: "AgentBoardCoreTests",
            dependencies: ["AgentBoardCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
