# Building GitN

## Prerequisites

| Tool | Min Version | Install |
|------|-------------|---------|
| macOS | 14.0 | — |
| Xcode Command Line Tools | — | `xcode-select --install` |
| Swift | 6.0+ | bundled with Xcode CLT |
| CMake | 3.22+ | `brew install cmake` |
| Node.js | 18+ | `brew install node` |

> All Homebrew installs at once:
> ```bash
> brew install cmake node
> ```

---

## First-time build

### 1. Clone the repo

```bash
git clone <repo-url>
cd GitN/GitN
```

### 2. Build Monaco editor bundle

Monaco source files are **not** committed to git. Build them once (or after a version bump):

```bash
./Scripts/build_monaco.sh
```

This runs `npm install` + `webpack` inside `Monaco/`, then syncs the output into
`Sources/GitN/Resources/Monaco/`. Your hand-crafted files (`host.js`, `host.css`,
`index.html`) are never touched.

Expected output:

```
Installing Monaco dependencies...
Building Monaco (this may take a minute)...
Syncing to Resources (preserving host.js, host.css, index.html)...
Monaco synced to .../Sources/GitN/Resources/Monaco
```

### 3. Build the app

```bash
./build.sh
```

`build.sh` runs all four steps automatically:

```
[0/4] Ensuring libgit2 source...     ← clones libgit2 v1.9.1 if missing
[1/4] Building Monaco editor...      ← skipped if already up to date
[2/4] Generating app icon...
[3/4] Building Swift package...
[4/4] Creating app bundle...
```

The finished app lands at:

```
build/GitN.app
```

Open it with:

```bash
open build/GitN.app
```

---

## Subsequent builds

`./build.sh` is all you need. It skips Monaco if nothing changed.

---

## Upgrading Monaco

1. Edit `Monaco/package.json`, bump `monaco-editor` (and optionally `monaco-editor-webpack-plugin`):

```json
"monaco-editor": "0.55.0",
"monaco-editor-webpack-plugin": "7.1.1"
```

2. Run the full build:

```bash
./build.sh
```

The Monaco step detects `package.json` is newer than the last build and rebuilds automatically.

To rebuild Monaco in isolation without rebuilding Swift:

```bash
./Scripts/build_monaco.sh
```

---

## Rebuilding libgit2 manually

libgit2 is cloned automatically by `build.sh`. You only need to run this manually
if you want to update the libgit2 version or rebuild the xcframework from scratch:

```bash
./build_libgit2.sh
```

This clones `libgit2 v1.9.1`, compiles it for `arm64` + `x86_64`, lipo-merges them,
and packages the result as `Clibgit2.xcframework`. Requires `cmake`.

To change the libgit2 version, set the env var before running:

```bash
LIBGIT2_VERSION=v1.9.2 ./build_libgit2.sh
```

---

## Project structure

```
GitN/
├── Monaco/                        # Monaco webpack project
│   ├── package.json               # ← Monaco version lives here
│   ├── webpack.config.js
│   └── src/entry.js
├── Scripts/
│   ├── build_monaco.sh            # Monaco build + sync
│   ├── ensure_libgit2.sh          # libgit2 source fetcher
│   └── generate_icon.swift
├── Sources/
│   ├── Clibgit2/                  # libgit2 C source (cloned on first build)
│   └── GitN/
│       └── Resources/Monaco/      # Monaco output (git-ignored, except below)
│           ├── host.js            ← custom WebKit bridge  (git-tracked)
│           ├── host.css           ← custom styles         (git-tracked)
│           └── index.html         ← HTML entry point      (git-tracked)
├── build.sh                       # Full build entry point
└── build_libgit2.sh               # Standalone libgit2 builder
```

## Codebase guide

For app architecture, screen structure, shared components, and current refactor hotspots, see:

```bash
DEVELOPMENT.md
```

---

## Troubleshooting

**`cmake: command not found`**
```bash
brew install cmake
```

**`node: command not found`**
```bash
brew install node
```

**Monaco build fails with webpack errors**
```bash
cd Monaco && rm -rf node_modules && npm install && npm run build
```

**Swift build fails with missing libgit2 symbols**

The xcframework may be stale. Rebuild it:
```bash
./build_libgit2.sh
```

**App won't open (Gatekeeper)**

The app is ad-hoc signed. If macOS blocks it:
```bash
xattr -dr com.apple.quarantine build/GitN.app
```
