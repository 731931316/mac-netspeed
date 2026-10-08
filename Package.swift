// swift-tools-version: 6.0
import PackageDescription

/// Defines the native application, platform adapter, and independently testable core.
let package = Package(
    name: "NetSpeed",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NetSpeed", targets: ["NetSpeedApp"]),
        .library(name: "NetSpeedCore", targets: ["NetSpeedCore"]),
        .library(name: "NetSpeedNetwork", targets: ["NetSpeedNetwork"])
    ],
    targets: [
        .target(name: "NetSpeedCore"),
        .target(name: "NetSpeedNetwork", dependencies: ["NetSpeedCore"]),
        .executableTarget(name: "NetSpeedApp", dependencies: ["NetSpeedCore", "NetSpeedNetwork"]),
        .testTarget(name: "NetSpeedCoreTests", dependencies: ["NetSpeedCore"]),
        .testTarget(name: "NetSpeedNetworkTests", dependencies: ["NetSpeedCore", "NetSpeedNetwork"])
    ]
)
