# Disk Visualizer

A lightweight macOS disk-usage visualizer. It scans a drive or folder, builds a
tree of file sizes, and renders it as an interactive sunburst chart with a
detail panel beside it — so you can see what is eating your disk instead of
guessing. SwiftUI, no third-party dependencies, macOS 14+.

## Features

- **Interactive sunburst** — hover for detail, click to select, double-click to
  drill down, breadcrumb to walk back up
- **Two palettes** — *Named* colors folders the way macOS Settings does;
  *File Type* groups everything into eight functional categories
- **Act on what you find** — reveal in Finder, copy the path, or move to Trash
  straight from the detail panel
- **Scan anything** — a whole volume, or any folder via `Scan Folder…`
- **Accurate totals** — hard-link dedup, app bundles sized by their contents,
  and the APFS volumes macOS hides from a normal walk are counted too
- **Fast on the second look** — scans are cached to disk, so reopening a drive
  takes about 0.4 s instead of a minute

## Requirements

- macOS 14 or later
- Swift 6.x — Command Line Tools is enough to build and run
  (`xcode-select --install`). Full Xcode is only needed for `swift test`, since
  the suite uses swift-testing.

## Install

Build it from source:

```bash
git clone https://github.com/Night-Vision/disk-visualizer.git
cd disk-visualizer
./scripts/package_app.sh
```

That produces `build/DiskVisualizer.app`. Drag it to `/Applications`.

The bundle is **ad-hoc signed**, so the first launch needs a right-click →
**Open** to get past Gatekeeper. To sign with a real Developer ID instead, set
`DEVELOPER_ID_APPLICATION` before running the script:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" ./scripts/package_app.sh
```

To build a drag-to-Applications disk image:

```bash
./scripts/create_installer.sh          # → build/DiskVisualizer-Installer.dmg
```

A prebuilt DMG will be attached to [Releases](https://github.com/Night-Vision/disk-visualizer/releases)
once the project is tagged.

For a quick development loop you can skip the bundle:

```bash
swift build -c release && swift run DiskVisualizer
```

Note that an unbundled binary cannot be granted Full Disk Access, so its totals
will read low — see below.

## Full Disk Access

This is the difference between right and wrong numbers. Without it, macOS hides
protected folders (Mail, Messages, Photos) from the scan and the total comes out
short.

Open **System Settings → Privacy & Security → Full Disk Access**, add
`DiskVisualizer.app`, then hit **Rescan**. The app shows a banner with an
**Open Privacy Settings** button that takes you straight there.

With access granted, a scan of `/` accounts for about **98.1%** of the drive's
used capacity — measured on a 178 GB APFS volume. The rest is APFS container
metadata, not missing files.

## Documentation

- [How it works](docs/INNER_WORKINGS.md) — architecture, scanning, colors, packaging
- [Inner Workings (styled)](docs/inner_workings.html) — the same document as a standalone page

## License

[MIT](LICENSE)
