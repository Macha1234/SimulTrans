// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimulTrans",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SimulTrans",
            path: "Sources/SimulTrans",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Translation"),
            ]
        ),
    ]
)
