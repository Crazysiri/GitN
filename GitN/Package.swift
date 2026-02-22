// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitN",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GitN", targets: ["GitN"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .systemLibrary(
            name: "Clibgit2",
            pkgConfig: "libgit2",
            providers: [.brew(["libgit2"])]
        ),
        .executableTarget(
            name: "GitN",
            dependencies: ["Clibgit2", "SwiftTerm"],
            path: "Sources/GitN"
        ),
    ]
)
