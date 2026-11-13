// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Grip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Grip", targets: ["Grip"]),
        .library(name: "GripCore", targets: ["GripCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.25.1"),
    ],
    targets: [
        // Platform-independent logic: models, risk math, Hyperliquid API + signing, storage.
        .target(
            name: "GripCore",
            dependencies: [.product(name: "libsecp256k1", package: "swift-secp256k1")]
        ),
        // The native macOS app (SwiftUI + AppKit).
        .executableTarget(
            name: "Grip",
            dependencies: ["GripCore"]
        ),
        .testTarget(
            name: "GripCoreTests",
            dependencies: ["GripCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
