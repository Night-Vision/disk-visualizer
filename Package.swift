// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskVisualizer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskVisualizer", targets: ["DiskVisualizerApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DiskVisualizerLib",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .executableTarget(
            name: "DiskVisualizerApp",
            dependencies: ["DiskVisualizerLib"],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "DiskVisualizerTests",
            dependencies: ["DiskVisualizerLib"]
        ),
        .executableTarget(
            name: "Benchmark",
            dependencies: ["DiskVisualizerLib"]
        ),
        .executableTarget(
            name: "Profiler",
            dependencies: ["DiskVisualizerLib"]
        )
    ]
)
