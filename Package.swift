// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimulTrans",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SimulTrans",
            path: "Sources/SimulTrans",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Translation"),
            ]
        ),
    ]
)
