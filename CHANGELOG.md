# DiskVisualizer Changelog

## Unreleased

- **Docs: Inner Workings v2 (two-tier rewrite)**
  - Added `docs/INNER_WORKINGS.md`, the canonical GitHub-rendered deep dive, with plain-language intros + expandable `<details>` code, a TL;DR, glossary, and source map.
  - Rewrote `docs/inner_workings.html` to mirror it: self-contained (no Google Fonts), styled `<details>` tiers.
  - Corrected stale claims (removed "lock-free", "100% byte-level", fabricated memory numbers) and documented `[other folders]` aggregation + per-ring binary-search hit testing.
  - Added `README.md` (install + build + docs links); now tracking `docs/` and `scripts/` in git.

- **macOS Drag-to-Applications DMG Installer Script**
  - Added `scripts/create_installer.sh` to package a native macOS `.dmg` installer with the classic drag-to-Applications layout.
  - Automatically handles CWD independence, robust `trap cleanup EXIT` unmounting, `600x380` Finder window bounds with 128px icons, and compressed `UDZO` output.
  - Supports production notarization (`NOTARIZE=true`) with `xcrun notarytool`, `stapler`, and `spctl` assessment.

- **Drill-down animation now only runs on double-click**
  - Double-clicking a folder wedge on the sunburst plays a smooth scale entrance animation into the new root.
  - Breadcrumb navigation, scan completion, and trash updates no longer trigger the transition.
  - Replaced the heavy SwiftUI view transition (which kept two full-resolution sunbursts alive) with a lightweight Canvas-internal scale animation, eliminating the CPU spike and lag on double-click.
  - Lowered the `Canvas` display-scale cap from 4× to 2.5× to keep memory usage safe while the new animation runs.

### 🎨 Visual
- **High-contrast dual-mode File Type palette & anti-mass-gray classification**
  - Grouped file extensions into 8 distinct functional categories: *Developer / Code*, *Executables & Binaries*, *Media*, *Documents & Data*, *Archives & Packages*, *Audio & Sound*, *System Caches & Logs*, and *Unclassified / Folders*.
  - Dual-mode dynamic colors powered by `NSColor` adapt automatically to macOS System Dark Mode vs. Light Mode.
  - Special name classification maps extensionless developer/system items (`.git`, `node_modules`, `.cache`, `.trash`, etc.) to their respective categories.
  - Sub-files and folders inherit their parent's category color with a depth lightness boost (`adjustLightness(by: depth * 0.08)`), preventing flat mass-gray slices.
  - Tiny extensionless files (< 1 MB) route to *System Caches & Logs* (muted Slate tone).
  - Category-based sorting in `SunburstLayout` and `DetailPanel` aligns wedges into contiguous visual color arcs.

- **Single-click select, double-click drill-down on the sunburst**
  - A single click on any wedge now selects it and updates the detail panel.
  - A double-click drills into that folder, zooming the sunburst into its children.
  - The previous double-tap-to-reset-zoom gesture has been replaced by a small overlay reset button that appears only while zoomed or panned.

- **Right-click on sunburst wedges → "Open in Finder"**
  - Right-clicking a wedge now opens a small contextual menu with a single "Open in Finder" item.
  - Selecting it reveals the corresponding file or folder in Finder, scoped to the wedge that was right-clicked — works for any reachable node, including the scanned root in the center hole.

- **Collapsible "Selected Details" inspector on the left sidebar**
  - Left-click any sunburst wedge OR any row in the right-side detail list to populate a new sticky (hover-independent) selection card in the sidebar.
  - The card shows the node's icon (SF Symbol by file extension), size with a thin bar of the selected drive's total capacity, child summary (`N items` / `50+ items` when overflow is folded), and last-modified timestamp.
  - The full POSIX path is shown with a one-click copy button.
  - Three actions: *Reveal in Finder*, *Move to Trash* (handles ancestor-aware cleanup so trashing a parent also clears the stale selection), and *Open in Terminal* (launches `Terminal.app` at the node via `/usr/bin/open`).
  - Header band stays visible when collapsed so the user can park a selection without taking up screen space.

- **Hidden files and folders are now silver**
  - Any node whose name begins with `.` is rendered in a silver/gray tone, making them easy to distinguish from regular folders.
- **Static “Move to Trash” button**
  - The trash button is now always visible in the detail panel and disabled only for the root node.
- **macOS Settings-style color palette**
  - Top-level folders now use the same distinct accent colors as macOS Settings icons for better accessibility and contrast.

- **Slightly enlarged loading window**
  - Bumped the parsing window's spinner (`PulsatingFlower`) from 180×180 to 240×240 for better visibility during long scans.

- **System folders now render as off-white**
  - Top-level macOS directories (`/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/opt`, `/private`, `/dev`, `/var`, `/cores`) now paint with a single solid off-white (`Color(red: 0.92, green: 0.93, blue: 0.95)`).
  - Replaces the previous alternating black/white 45° diagonal hatch, which user feedback flagged as visually noisy on the dark canvas.

- **macOS cache/temp folders now render as soft amber**
  - Locations safe to clean periodically: `/Library/Caches`, `/System/Library/Caches`, `/private/var/folders` (per-user temp autoset by `confstr _CS_DARWIN_USER_TEMP_DIR`), `/private/tmp` and `/tmp` (the symlink alias), `/private/var/tmp`, plus the user-home `~/Library/Caches`, `~/Library/Logs`, `~/Library/Application Support/CrashReporter`, `~/Library/Developer/CoreSimulator/Caches`, and `~/Library/Developer/Xcode/DerivedData`.
  - All of these now paint with a single solid amber (`Color(red: 0.95, green: 0.78, blue: 0.30)`) — easier on the eyes than full hazard yellow, still distinct from the muted regular palette.
  - Rule precedence unchanged: cache category beats system category, so e.g. `/System/Library/Caches/*` still gets the amber fill.

- **PulsatingFlower now does a spin-out entrance and pop-in/out wave**
  - The loading spinner used to just pop in and start pulsing. The 12 petals now fly outward from the center over 600 ms (easeOut) before the traveling pop wave takes over.
  - Each petal scales from 0 to 1.5× and fades in and out as the wave peak orbits the ring, giving the loading state a lively "bubbles popping" feel.
  - Reduced the continuous cycle duration from 4.0 s to 1.5 s for a snappier loading feel.
  - Respects `accessibilityReduceMotion`: the resting flower appears immediately for users who disable motion.

- **Inspector action buttons are now icon-only**
  - The Finder / Trash / Terminal buttons in the sidebar inspector card dropped their text labels (`Fin…`, `Tra…`, `Ter…`) which were being truncated by sidebar width. The three icons (`folder`, `trash`, `terminal`) remain, with hover tooltips and VoiceOver labels intact.

- **Breadcrumb path buttons are now native `.bordered`**
  - The path at the top of the app renders as native bordered buttons (Liquid Glass on macOS 26) so they read as clickable, with the current location grayed out and disabled as a "you are here" cue.

### ⚡ Performance
- **FileNode is now a 16-byte struct over a flat array**
  - `FileNode` was a heap-allocated class (~200+ bytes each: UUID, URL, name, children array, class header). It's now a struct wrapping a `(NodeStore, Int)` index pair, with all node data in a single contiguous `[CompactNode]`. Full-disk scans with tens of thousands of nodes save tens of MB and drop per-node allocation churn.
- **Hard-link dedup no longer hops through an actor per file**
  - `InodeTracker` was an `actor`, so every hard-linked file (`linkCount > 1`, common under `/System` and Xcode toolchains) paid an actor-hop to call `mark`. It's now a plain class guarded by an `OSAllocatedUnfairLock`; the call is a lock/unlock on the current thread.
- **Hover/click hit-testing is O(log n) per ring**
  - The sunburst's hit-test used to linearly scan every segment per mouse move. Segments within each depth ring form a contiguous angle-partitioned array, so hover now binary-searches the ring in O(log n). No more full O(n) scan on every hover frame.
- **Wedge colors are computed once per tree change, not per frame**
  - `paletteColor` (which round-trips through `NSColor` for lightness adjustment) was called for every segment in every `draw()` pass. Colors are now cached in a parallel `segmentColors` array at rebuild time and only recomputed when the tree, root, or color scheme changes.
- **Window resize no longer rebuilds segments or colors**
  - Segment angles derive from byte sizes and colors from node/root/scheme — neither depends on canvas size. Resizing now only recomputes the cached ring width instead of discarding and rebuilding both arrays on every resize frame.
- **Detail panel no longer re-sorts children on every render**
  - The right-side list sorted `children` by size on every body evaluation. It now renders the store's maintained size-descending order directly.
- **Modification dates use `FormatStyle` instead of a `DateFormatter` per call**
  - `formattedModificationDate` no longer constructs a fresh ICU-backed `DateFormatter` for each node.
- **Hard-link dedup without a second stat syscall**
  - `InodeTracker` now keys on `fileResourceIdentifier` / `volumeIdentifier`, which arrive with the same bulk resource fetch the scanner already performs. The previous per-file `attributesOfItem(atPath:)` for every file with `linkCount > 1` is gone, so link-heavy trees (`/System`, Xcode toolchains) no longer stall the 16 concurrent scan tasks on blocking stats.
- **Deep-subtree size aggregation is now parallel**
  - `aggregateDeepSize` at depth ≥ 8 used to walk remaining subdirectories sequentially. It now batches them 16 at a time through `withThrowingTaskGroup` (per-directory walk in `aggregateOneSubdir`), matching the parallel subdirectory scan; cancellation still propagates.
- **Faster full-drive scans**
  - Eliminated per-item `Set` allocation in the hot enumeration loop by pre-computing the resource-key set once.
  - Short-circuited package detection to avoid unnecessary string operations.
  - Reduced cancellation-check frequency to every 256 items while keeping progress flushes every 1024 items, dramatically lowering context-switch overhead on drives with millions of files.
- **Removed one wasted tree level**
  - `maxDepth` now matches the sunburst’s visual depth so the scanner no longer allocates nodes that are never drawn.

- **Yield in the hot enumeration loop**
  - Added `await Task.yield()` inside the every-256-items cancellation gate of `DiskScanner.scan()`, so on whole-disk scans the MainActor actually gets a chance to drain.
  - Resolves progress counters appearing frozen at intermediate values (e.g. 63 GB / 87 GB) between flush windows.

- **Sunburst stays crisp while zooming in**
  - Raised the `Canvas` display-scale cap from 2× to 4× so the sunburst wedges remain sharp at higher zoom levels.

- **Yield + skip-guard in `aggregateDeepSize`**
  - The shallow-scan aggregate walker (`aggregateDeepSize`) used to have only `try Task.checkCancellation()` in its per-256-item gate — no `Task.yield()`. `await progress.add(...)` is an actor call, and Swift fast-paths uncontended actors through the current thread without actually suspending, so the cooperative-thread slice was held for multi-second windows when walking shallow-scan monoliths (`/private`, `/Library`, `/System`, `/opt`, `/dev`), starving the MainActor and freezing the spinner. Added `await Task.yield()` immediately after the cancellation check.
  - Same loop now honors `Self.shouldSkip(_:)` so it doesn't follow the firmlink into the APFS data volume at `/System/Volumes/Data` (`skipRootPaths`) — saving an extra full pass over that volume per shallow-scan root.

- **Cached scans actually load instead of re-walking**
  - The on-disk cache was write-only: saved after every scan but never read back, so every launch did a full filesystem walk. `DiskScanner.scan` now loads the saved JSON off-main before walking (`ScanCache.load`); a hit skips the walk entirely. A miss, corrupt file, or old-format cache falls through to a full scan and is re-saved (self-healing). Rescan (`ignoreCache: true`) forces the walk.

### 🐛 Fixes
- **Detail list stays sorted after trashing files**
  - Trashing a node shrank its siblings but left them in a stale order, which the detail panel's per-render sort had been masking. `removeFromTree` now restores the size-descending `childIndices` order at the mutation boundary, and the detail panel trusts the store's order.
  - The invariant is now structural: `setChildren` sorts at the store's write boundary, so every caller (the scanner, tests, any future mutation) gets size-descending order without remembering to sort.
- **Hidden system directories are skipped again**
  - The `skipRootHiddenPrefixes` check (`.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.vol`) compared absolute paths against relative names, so it never matched. It now matches `url.lastPathComponent`, catching these directories at the root of any volume, not just the boot volume.
- **Duplicate counting on full-disk scans**
  - Added skip rules for `/System/Volumes`, `/Volumes`, `/home`, `/net`, `/Network`, and hidden root prefixes so APFS firmlinks and automounts are no longer double-counted.
- **Loading indicator now appears immediately**
  - Added `Task.yield()` at the start of the scan so the loading flower renders before the cache load and filesystem walk begin.

- **Drive rows now scan via the selection binding**
  - Selecting a drive in the sidebar reliably starts a scan, including keyboard arrow navigation and programmatic selection.
  - Replaces a broken-on-macOS pattern where `List(selection:)` would swallow row clicks before the per-row `.onTapGesture` fired, leaving the drive row looking unresponsive.

- **App no longer crashes when trashing a folder**
  - `removeFromTree` sorted `nodes[parent].childIndices` in place while the sort predicate read the same array, tripping Swift's exclusivity checker (runtime abort — "simultaneous accesses"). It now sorts a local copy and writes it back.
- **Detail panel no longer shows a stale node after trashing**
  - Trashing the hovered node (or an ancestor of it) left `hoveredNode` pointing at a now-zeroed/orphaned node, so the right panel kept showing it until the next hover. `trash()` now clears `hoveredNode` with the same ancestor guard it already applied to `selectedNode`.

### 📚 Documentation
- Added `CLAUDE.md`, a comprehensive AI-agent reference covering architecture, file-by-file reference, data flow, common gotchas, and a Mermaid diagram.
