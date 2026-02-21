// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GitX", targets: ["GitX"]),
    ],
    targets: [
        .systemLibrary(
            name: "Clibgit2",
            pkgConfig: "libgit2",
            providers: [.brew(["libgit2"])]
        ),
        .executableTarget(
            name: "GitX",
            dependencies: ["Clibgit2"],
            path: "Sources/GitX"
        ),
    ]
)
