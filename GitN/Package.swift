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
        // libgit2 compiled from source (submodule at Sources/Clibgit2/libgit2).
        // No cmake or pre-build steps needed — Xcode and `swift build` both work directly.
        .target(
            name: "Clibgit2",
            path: "Sources/Clibgit2",
            exclude: [
                // ── Windows-only ──
                "libgit2/src/util/win32",

                // ── Unused hash backends (would cause duplicate symbols or missing headers) ──
                "libgit2/src/util/hash/openssl.c",
                "libgit2/src/util/hash/openssl.h",
                "libgit2/src/util/hash/mbedtls.c",
                "libgit2/src/util/hash/mbedtls.h",
                "libgit2/src/util/hash/win32.c",
                "libgit2/src/util/hash/win32.h",
                "libgit2/src/util/hash/builtin.c",
                "libgit2/src/util/hash/builtin.h",
                "libgit2/src/util/hash/rfc6234",

                // ── Unused deps ──
                "libgit2/deps/chromium-zlib",
                "libgit2/deps/pcre",
                "libgit2/deps/winhttp",
                "libgit2/deps/zlib",

                // ── Unused ntlmclient crypto/unicode backends ──
                "libgit2/deps/ntlmclient/crypt_openssl.c",
                "libgit2/deps/ntlmclient/crypt_openssl.h",
                "libgit2/deps/ntlmclient/crypt_mbedtls.c",
                "libgit2/deps/ntlmclient/crypt_mbedtls.h",
                "libgit2/deps/ntlmclient/crypt_builtin_md4.c",
                "libgit2/deps/ntlmclient/unicode_builtin.c",
                "libgit2/deps/ntlmclient/unicode_builtin.h",

                // ── Non-source files ──
                "libgit2/deps/llhttp/LICENSE-MIT",
                "libgit2/deps/llhttp/CMakeLists.txt",
                "libgit2/deps/ntlmclient/CMakeLists.txt",
                "libgit2/deps/xdiff/CMakeLists.txt",
                "libgit2/src/libgit2/CMakeLists.txt",
                "libgit2/src/libgit2/git2.rc",
                "libgit2/src/libgit2/config.cmake.in",
                "libgit2/src/libgit2/experimental.h.in",
                "libgit2/src/util/CMakeLists.txt",
                "libgit2/src/util/git2_features.h.in",

                // ── Non-source directories ──
                "libgit2/ci",
                "libgit2/cmake",
                "libgit2/docs",
                "libgit2/examples",
                "libgit2/fuzzers",
                "libgit2/script",
                "libgit2/tests",
                "libgit2/src/cli",
            ],
            sources: [
                "libgit2/src/libgit2",
                "libgit2/src/util",
                "libgit2/deps/llhttp",
                "libgit2/deps/ntlmclient",
                "libgit2/deps/xdiff",
            ],
            publicHeadersPath: "include",
            cSettings: [
                // Header search paths
                .headerSearchPath("libgit2/include"),
                .headerSearchPath("libgit2/src/libgit2"),
                .headerSearchPath("libgit2/src/util"),
                .headerSearchPath("libgit2/deps/llhttp"),
                .headerSearchPath("libgit2/deps/ntlmclient"),
                .headerSearchPath("libgit2/deps/xdiff"),
                .headerSearchPath("generated"),

                // NTLM client
                .define("NTLM_STATIC", to: "1"),
                .define("UNICODE_ICONV", to: "1"),
                .define("CRYPT_COMMONCRYPTO"),

                // SHA1 collision detection
                .define("SHA1DC_NO_STANDARD_INCLUDES", to: "1"),
                .define("SHA1DC_CUSTOM_INCLUDE_SHA1_C", to: "\"git2_util.h\""),
                .define("SHA1DC_CUSTOM_INCLUDE_UBC_CHECK_C", to: "\"git2_util.h\""),

                // Disable clang modules to avoid struct name clashes with system headers
                .unsafeFlags(["-fno-modules"]),
            ]
        ),
        .executableTarget(
            name: "GitN",
            dependencies: ["Clibgit2", "SwiftTerm"],
            path: "Sources/GitN",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
                .linkedFramework("Security"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
    ]
)
