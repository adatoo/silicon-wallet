// swift-tools-version: 6.2
// All non-UI logic for Silicon Wallet (DESIGN.md §3). The app target talks only to this package.
import PackageDescription

let package = Package(
    name: "SiliconWalletKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SiliconWalletKit", targets: ["SiliconWalletKit"])
    ],
    dependencies: [
        // Argon2id only (ADR-0006). An exact pin; check its licence (ISC) before bumping.
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.11.0")
    ],
    targets: [
        .target(
            name: "SiliconWalletKit",
            dependencies: [.product(name: "Clibsodium", package: "swift-sodium")],
            swiftSettings: [.treatAllWarnings(as: .error)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "SiliconWalletKitTests",
            dependencies: ["SiliconWalletKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
