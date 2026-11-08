// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PadelCore",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "PadelCore", targets: ["PadelCore"]),
    ],
    targets: [
        .target(name: "PadelCore"),
        .testTarget(name: "PadelCoreTests", dependencies: ["PadelCore"]),
    ]
)
