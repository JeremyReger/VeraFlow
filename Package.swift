// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VeraFlow",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "VeraFlow",
            targets: ["VeraFlow"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "VeraFlow",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio", condition: .when(platforms: [.iOS, .macOS]))
            ],
            path: "VeraFlow",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "VeraFlowTests",
            dependencies: ["VeraFlow"],
            path: "VeraFlowTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
