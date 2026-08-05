# DiskVisualizer — Inner Workings

*How a lightweight macOS disk-usage visualizer works, end to end. macOS 14+, Swift 5.9. The README covers install & usage; this is the deep dive.*

## TL;DR

DiskVisualizer scans a folder or volume, builds a tree of file sizes, and draws it as an interactive sunburst chart.

- **Scan** walks the tree with up to 16 parallel workers, fetching file metadata in bulk — one system call per directory, not one per file.
- **Accurate** hard links are counted once (inode dedup); root totals are exact.
- **Fast** a disk cache skips re-scanning unchanged paths; deep or wide trees are folded into `[other folders]` so the wheel stays readable.
- **Color** two palette modes: file-type categories, or macOS-Settings-style folder colors.
- **Light** a flat-array storage engine keeps full-disk scans in the tens of MB.

## 1. System architecture

Data flows through six layers, each with one job:

> macOS VFS → DiskScanner → InodeTracker → NodeStore → SunburstLayout → SunburstCanvas

<details>
<summary>Layer-by-layer (under the hood)</summary>

| Layer | Job |
|---|---|
| macOS VFS | Kernel file-system metadata, fetched in bulk via `URLResourceKey`s |
| DiskScanner | Walks directories with `withTaskGroup`, up to 16 concurrent workers |
| InodeTracker | De-duplicates hard links so a file counts once |
| NodeStore | Flat `[CompactNode]` array; every node is a 16-byte struct |
| SunburstLayout | Turns the tree into polar wedges (angle ∝ size) |
| SunburstCanvas | Renders wedges on a SwiftUI `Canvas` and hit-tests pointer events |

</details>

## 2. Backend: scanning engine

**What it does.** One scan is one pass over the tree. The scanner asks macOS for every file's size, kind, link count, and identity in a single bulk call per directory instead of one stat call per file, and walks directories with up to 16 parallel workers. Both hot loops yield to the main thread every 256 items so the UI stays responsive during whole-disk scans.

<details>
<summary>Bulk resource fetch (under the hood)</summary>

The keys requested per directory (`Sources/DiskVisualizerLib/DiskScanner.swift`):

```swift
private static let resourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isPackageKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .linkCountKey,
    .contentModificationDateKey,
    .fileResourceIdentifierKey,  // hard-link identity
    .volumeIdentifierKey
]

let contents = try FileManager.default.contentsOfDirectory(
    at: node.url,
    includingPropertiesForKeys: resourceKeys,
    options: [.skipsSubdirectoryDescendants]
)
```

</details>

**Hard links.** Two names pointing at the same file must count once, or `/System` and Xcode toolchains double-count. Each file's `fileResourceIdentifier` + `volumeIdentifier` is inserted into a set; the first insert wins and duplicates are skipped.

<details>
<summary>InodeTracker (under the hood)</summary>

```swift
final class InodeTracker: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<FileIdentity>())

    func mark(file: (any NSObjectProtocol & NSCopying & NSSecureCoding)?,
              volume: (any NSObjectProtocol & NSCopying & NSSecureCoding)?) -> Bool {
        lock.withLock { state in
            guard let file = file as? NSObject,
                  let volume = volume as? NSObject else { return true }
            return state.insert(FileIdentity(file: AnyHashable(file),
                                             volume: AnyHashable(volume))).inserted
        }
    }
}
```

A plain lock, not an actor — hard-linked files don't pay an actor-hop per file.

</details>

## 3. Frontend: polar geometry

**What it does.** The sunburst is a polar bar chart: each folder's bytes are a slice of the circle, sized proportionally — a file using half a folder's bytes gets half the angle.

<details>
<summary>Angle & ring math (under the hood)</summary>

```swift
let fraction = Double(child.size) / Double(total)
let slice = (end - start) * fraction

let innerRadius = centerHoleRadius + CGFloat(depth - 1) * ringWidth
let outerRadius = centerHoleRadius + CGFloat(depth) * ringWidth - ringGap
```

Constants: `centerHoleRadius = 44`, `ringGap = 1`, at most `maxDepth = 8` rings.

</details>

**Hit-testing.** Pointer events are converted to polar coordinates with `atan2`, then each ring is searched with a binary search (wedges within a ring are angle-sorted), so hover is O(log n) per ring rather than a scan of every wedge.

<details>
<summary>Polar hit-test (under the hood)</summary>

```swift
let dx = point.x - center.x
let dy = point.y - center.y
let distance = hypot(dx, dy)
var angle = atan2(dy, dx)
if angle < 0 { angle += .pi * 2 }
let depth = Int((distance - centerHoleRadius) / ringWidth) + 1
let ring = segmentsByDepth[depth]   // binary search within the ring
```

</details>

**Aggregation.** Wide directories keep at most 50 children (`maxChildrenPerNode`), and anything past depth 8 is folded into an `[other folders]` wedge, so a huge tree stays a readable 8 rings.

## 4. Color: dual-mode palette

**What it does.** Left to defaults, every wedge would be the same gray and the wheel would be unreadable. *File Type* mode classifies each node into one of 8 functional categories, each with a distinct color that has dark and light variants and adapts to the macOS appearance. *Named* mode colors by top-level folder instead.

| Category | Dark | Light | Examples |
|---|---|---|---|
| Developer / Code | `#2DD4BF` | `#0D9488` | `.swift`, `.js`, `.py`, `.git/`, `node_modules/` |
| Executables & Binaries | `#EC4899` | `#DB2777` | `.app`, `.dylib`, `.bin`, `.framework` |
| Media (Images/Video) | `#F43F5E` | `#E11D48` | `.png`, `.jpg`, `.heic`, `.mp4`, `.mov` |
| Documents & Data | `#FACC15` | `#D97706` | `.pdf`, `.docx`, `.xlsx`, `.txt`, `.csv` |
| Archives & Packages | `#A855F7` | `#9333EA` | `.zip`, `.tar.gz`, `.dmg`, `.pkg` |
| Audio & Sound | `#FB923C` | `#EA580C` | `.mp3`, `.wav`, `.flac`, `.m4a` |
| System Caches & Logs | `#64748B` | `#475569` | `.cache`, `.log`, `.tmp`, files < 1 MB |
| Unclassified / Folders | `#38BDF8` | `#0284C7` | directories & unclassified items |

**Anti-mass-gray rules.** Three rules keep the wheel from flattening into solid gray:
- **Ancestor inheritance** — everything inside a categorized tree (e.g. `.git/`, `node_modules/`) inherits its parent's category.
- **Depth boost** — sub-slices lighten slightly per ring (`adjustLightness(by: depth * 0.08)`).
- **Small-file grouping** — extensionless files under 1 MB map to the muted *System Caches & Logs* tone.

## 5. Memory optimizations

**What it does.** An earlier version stored every file as a heap object (~200+ bytes each) and serialized whole trees as JSON — full-disk scans ran into gigabytes of RAM. The tree now lives in a flat array of 16-byte structs, the cache is capped, and inode keys are value identifiers instead of heap strings.

<details>
<summary>Before / after (under the hood)</summary>

- **Before:** `@Observable FileNode` classes (~200+ bytes/file), multi-GB JSON string blobs, `Set<String>` inode keys.
- **After:** flat `[CompactNode]` (16 bytes/node), cache limited to ≤ 50,000 nodes (`ScanCache.swift`), inode dedup keyed on value identifiers.

A full-disk scan now sits in the tens of MB. *(Exact numbers aren't pinned down — nothing in the repo measures them.)*

</details>

## 6. Packaging & notarization

**What it does.** One script turns the SPM build into a drag-to-Applications DMG installer, with an optional notarized production path.

<details>
<summary>Pipeline (under the hood)</summary>

1. **SPM build** — `swift build -c release`
2. **Bundle assembly** — `DiskVisualizer.app` with `Info.plist` + `AppIcon.icns`
3. **Code signing** — Developer ID identity, or ad-hoc (`-s -`)
4. **DMG creation** — staging folder with `ln -s /Applications`, mounted as a read-write image
5. **Finder layout** — AppleScript sets the window bounds, 128px icons, flushes `.DS_Store`
6. **Notarize & staple** — `xcrun notarytool`, `stapler`, `spctl` when `NOTARIZE=true`

```bash
./scripts/create_installer.sh                                   # ad-hoc local build
NOTARIZE=true DEVELOPER_ID_APPLICATION="…" KEYCHAIN_PROFILE="…" ./scripts/create_installer.sh
```

</details>

## 7. Glossary

| Term | Meaning |
|---|---|
| VFS | The kernel's virtual file-system layer that serves metadata |
| Inode | The kernel's per-file record; two names can share one inode (hard link) |
| Hard link | A second name for the same file — must be counted once for accurate usage |
| Firmlink | APFS's directory-level link (e.g. `/System/Volumes/Data`) — skipped to avoid double counting |
| Task group | Swift Concurrency's `withTaskGroup`; runs up to N workers in parallel |
| UDZO | Compressed read-only DMG format (`hdiutil convert -format UDZO`) |
| Ad-hoc signature | Code-signed with `-` (no Apple identity); downloaded builds need right-click → Open |
| Notarization | Apple's server-side check + stapled ticket for frictionless installs |

## 8. Source map

| File | Job |
|---|---|
| [`DiskVisualizerApp.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerApp/DiskVisualizerApp.swift) | `@main` entry, creates the `WindowGroup` |
| [`Volume.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/Volume.swift) | Mounted-volume list for the sidebar |
| [`DiskScanner.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/DiskScanner.swift) | The scan engine (bulk fetch, task groups, aggregation) |
| [`InodeTracker.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/InodeTracker.swift) | Hard-link dedup |
| [`NodeStore.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/NodeStore.swift) | Flat-array storage + all mutations |
| [`ScanCache.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/ScanCache.swift) | JSON cache, capped at 50,000 nodes |
| [`SunburstLayout.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/SunburstLayout.swift) | Polar wedge geometry + category sorting |
| [`SunburstView.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/SunburstView.swift) | Canvas render, camera, hit-testing |
| [`ColorExtensions.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/ColorExtensions.swift) | Palettes + `FileTypeCategory` |
| [`ContentView.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Sources/DiskVisualizerLib/ContentView.swift) | Main view + app state |
| [`DiskVisualizerTests.swift`](https://github.com/Night-Vision/disk-visualizer/blob/main/Tests/DiskVisualizerTests/DiskVisualizerTests.swift) | XCTest suite |
