// swift-tools-version: 6.2
// All non-UI logic for Silicon Wallet (DESIGN.md §3). The app target talks only to this package.
import PackageDescription

let package = Package(
    name: "SiliconWalletKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SiliconWalletKit", targets: ["SiliconWalletKit"])
    ],
    targets: [
        .target(
            name: "SiliconWalletKit",
            exclude: ["Crypto/.gitkeep", "Model/.gitkeep", "Store/.gitkeep", "Sync/.gitkeep", "Vault/.gitkeep"],
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
