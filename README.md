# DiskVisualizer

Lightweight macOS disk-usage visualizer. Scans drives and folders, builds a tree of file sizes, and renders it as an interactive sunburst chart with a side detail panel. macOS 14+, Swift.

## Features

- Interactive sunburst: hover → detail, click → select, double-click → drill down
- Two color schemes: file-type categories (8-way legend) or macOS-Settings-style folder colors
- Right-click a wedge → "Open in Finder"; move to Trash from the app; copy the path
- Hard-link dedup (APFS) and a disk cache for fast rescans

## Install

**Casual:** download `DiskVisualizer-Installer.dmg` from [Releases](https://github.com/Night-Vision/disk-visualizer/releases), open it, drag the app to Applications. Ad-hoc builds: right-click → Open to bypass Gatekeeper.

**From source:**

```bash
swift build -c release
swift test
swift run DiskVisualizer
```

**Build the DMG installer:**

```bash
./scripts/create_installer.sh
```

## Documentation

- [How it works](docs/INNER_WORKINGS.md) — architecture, scanning, colors, and packaging
- [Inner Workings (styled)](docs/inner_workings.html) — the same doc, as a standalone page

## License

MIT
