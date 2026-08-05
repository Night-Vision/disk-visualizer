import SwiftUI
import AppKit

// MARK: - Color scheme mode

enum ColorSchemeMode: String, CaseIterable {
    case named
    case fileType

    var label: String {
        switch self {
        case .named:   "Named"
        case .fileType: "File Type"
        }
    }
}

struct ColorSchemeModeKey: EnvironmentKey {
    static let defaultValue: ColorSchemeMode = .named
}

extension EnvironmentValues {
    var colorSchemeMode: ColorSchemeMode {
        get { self[ColorSchemeModeKey.self] }
        set { self[ColorSchemeModeKey.self] = newValue }
    }
}

// MARK: - Color palette

extension Color {
    // MARK: - Root color map

    /// Named root-folder swatches. Every file/folder under one of these paths
    /// inherits that root's hue, with lightness boosted per depth level.
    private static let rootColorMap: [(prefix: String, color: Color)] = [
        ("/Users",        Color(red: 0.220, green: 0.741, blue: 0.969)), // #38BDF8 Sky Blue
        ("/System",       Color(red: 0.659, green: 0.333, blue: 0.969)), // #A855F7 Purple
        ("/Library",      Color(red: 0.961, green: 0.620, blue: 0.039)), // #F59E0B Amber
        ("/private",      Color(red: 0.063, green: 0.725, blue: 0.506)), // #10B981 Emerald
        ("/Applications", Color(red: 0.925, green: 0.282, blue: 0.596)), // #EC4899 Pink
        ("/usr",          Color(red: 0.580, green: 0.639, blue: 0.722)), // #94A3B8 Slate Gray
        ("/bin",          Color(red: 0.580, green: 0.639, blue: 0.722)), // #94A3B8 Slate Gray
        ("/opt",          Color(red: 0.278, green: 0.333, blue: 0.412)), // #475569 Dark Charcoal
        ("/dev",          Color(red: 0.278, green: 0.333, blue: 0.412)), // #475569 Dark Charcoal
        ("/var",          Color(red: 0.278, green: 0.333, blue: 0.412)), // #475569 Dark Charcoal
        ("/cores",        Color(red: 0.278, green: 0.333, blue: 0.412)), // #475569 Dark Charcoal
    ]

    // MARK: - User subfolder color map

    /// Common user-directory swatches. Only applies when the node's path is
    /// under `/Users/<username>/`.
    private static let subfolderColorMap: [String: Color] = [
        "Documents": Color(red: 0.980, green: 0.800, blue: 0.082),  // #FACC15 Electric Gold
        "Downloads": Color(red: 0.984, green: 0.573, blue: 0.235),  // #FB923C Warm Orange
        "Developer": Color(red: 0.176, green: 0.831, blue: 0.749),  // #2DD4BF Teal
        "Pictures":  Color(red: 0.957, green: 0.247, blue: 0.369),  // #F43F5E Rose Pink
        "Movies":    Color(red: 0.882, green: 0.114, blue: 0.282),  // #E11D48 Deep Coral
        "Music":     Color(red: 0.655, green: 0.953, blue: 0.816),  // #A7F3D0 Mint Green
        "Desktop":   Color(red: 0.506, green: 0.549, blue: 0.973),  // #818CF8 Periwinkle
    ]

    // MARK: - File-type color constants

    private static let fuchsiaPurple = Color(red: 0.753, green: 0.518, blue: 0.988) // #C084FC
    private static let warmAmber     = Color(red: 0.984, green: 0.584, blue: 0.235) // #FB923C
    private static let indigoBlue    = Color(red: 0.388, green: 0.400, blue: 0.945) // #6366F1
    private static let emeraldGreen  = Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981
    private static let cyan          = Color(red: 0.024, green: 0.714, blue: 0.831) // #06B6D4
    private static let roseRed       = Color(red: 0.957, green: 0.247, blue: 0.369) // #F43F5E
    private static let slateGray       = Color(red: 0.278, green: 0.333, blue: 0.412) // #475569 Dark Slate
    private static let mutedCharcoal   = Color(red: 0.294, green: 0.333, blue: 0.388) // #4B5563
    private static let unknownFileGray = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF Neutral Gray

    // MARK: - Fallback / misc constants

    /// Cool Slate (#94A3B8) — for aggregated nodes.
    private static let coolSlate   = Color(red: 0.580, green: 0.639, blue: 0.722)
    /// Soft Crimson (#FB7185) — for cache / temp / log paths.
    private static let softCrimson = Color(red: 0.984, green: 0.443, blue: 0.522)

    /// Tableau 10-style high-contrast palette fallback for root-level paths
    /// not matched by any named map.
    private static let highContrastPalette: [Color] = [
        Color(red: 0.306, green: 0.475, blue: 0.655),
        Color(red: 0.949, green: 0.557, blue: 0.169),
        Color(red: 0.882, green: 0.341, blue: 0.349),
        Color(red: 0.463, green: 0.718, blue: 0.698),
        Color(red: 0.349, green: 0.631, blue: 0.310),
        Color(red: 0.929, green: 0.788, blue: 0.282),
        Color(red: 0.690, green: 0.478, blue: 0.631),
        Color(red: 1.000, green: 0.616, blue: 0.655),
        Color(red: 0.612, green: 0.459, blue: 0.373),
        Color(red: 0.729, green: 0.690, blue: 0.675),
    ]

    // MARK: - Depth-based lightness adjustment

    /// Return a new `Color` whose HSB brightness is scaled by `(1 + factor)`.
    /// Clamps to 1.0. Keeps hue and saturation unchanged.
    func adjustLightness(by factor: Double) -> Color {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let newBrightness = min(1.0, brightness * (1.0 + factor))
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(newBrightness), opacity: Double(alpha))
    }

    // MARK: - Name helpers

    private static func rootColor(for url: URL) -> Color? {
        let path = url.path
        return rootColorMap.first { path == $0.prefix || path.hasPrefix($0.prefix + "/") }?.color
    }

    private static func isUnderUsers(_ url: URL) -> Bool {
        let comps = url.pathComponents
        return comps.count >= 3 && comps[1] == "Users"
    }

    private static func isGeneratedMisc(_ name: String) -> Bool {
        if name == "[other folders]" || name == "[deeper items]" { return true }
        return name.hasPrefix("[") && name.hasSuffix(" smaller files]")
    }

    // MARK: - File-type extension sets

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg"
    ]
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "svg", "gif", "webp", "bmp", "tiff", "tif"
    ]
    private static let documentExtensions: Set<String> = [
        "pdf", "pages", "docx", "doc", "txt", "rtf", "xlsx", "xls", "pptx", "ppt",
        "key", "numbers", "md", "csv", "tsv"
    ]
    private static let codeExtensions: Set<String> = [
        "swift", "py", "cpp", "c", "h", "hpp", "json", "db", "js", "ts", "go",
        "rs", "java", "rb", "sh", "bash", "zsh", "yaml", "yml", "toml", "xml",
        "sqlite", "sql", "plist", "strings", "xcconfig", "entitlements"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "aiff", "alac"
    ]
    private static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "gzip", "dmg", "iso", "7z", "rar", "bz2", "xz",
        "zst", "pkg"
    ]
    private static let binaryExtensions: Set<String> = [
        "app", "dylib", "bin", "exec", "framework", "kext", "bundle", "so",
        "o", "a", "dSYM"
    ]

    // MARK: - Ancestor-chain color lookup (named scheme)

    private static func findNamedColor(for node: FileNode, root: FileNode) -> (Color, Int)? {
        let ancestor = node.topLevelAncestor(under: root)
        var current: FileNode? = node
        while let c = current {
            let name = c.name
            if isGeneratedMisc(name) {
                return (coolSlate, c.depth)
            }
            if isUnderUsers(c.url), let color = subfolderColorMap[name] {
                return (color, c.depth)
            }
            if c == ancestor { break }
            current = c.parent
        }
        if let color = rootColor(for: ancestor.url) {
            return (color, ancestor.depth)
        }
        return nil
    }

    // MARK: - File-type color

    /// Return a flat category colour for a non-directory node based on its
    /// file extension. Directories and generated aggregate nodes get a muted
    /// neutral.
    private static func fileTypeColor(for node: FileNode) -> Color {
        let ext = node.url.pathExtension.lowercased()
        if videoExtensions.contains(ext)   { return fuchsiaPurple }
        if imageExtensions.contains(ext)   { return warmAmber }
        if documentExtensions.contains(ext) { return indigoBlue }
        if codeExtensions.contains(ext)    { return emeraldGreen }
        if audioExtensions.contains(ext)   { return cyan }
        if archiveExtensions.contains(ext) { return roseRed }
        if binaryExtensions.contains(ext)  { return slateGray }
        return unknownFileGray
    }

    // MARK: - Public palette entry points

    /// Determine the display colour for a node in the sunburst or its legend.
    ///
    /// - Parameter scheme: `.named` (default) for path-based root/subfolder
    ///   colours with depth-based lightness boost; `.fileType` for
    ///   extension-based category colours (flat, no depth adjustment).
    static func paletteColor(
        for node: FileNode,
        root: FileNode,
        scheme: ColorSchemeMode = .named
    ) -> Color {
        switch scheme {
        case .named:
            return namedPaletteColor(for: node, root: root)
        case .fileType:
            return fileTypePaletteColor(for: node, root: root)
        }
    }

    // MARK: - Named palette

    private static func namedPaletteColor(for node: FileNode, root: FileNode) -> Color {
        // 1. Hidden → silver.
        if node.name.hasPrefix(".") {
            return Color(red: 0.78, green: 0.80, blue: 0.82)
        }

        // 2. Cache → Soft Crimson.
        if NodeCategory.categorize(node.url) == .cache {
            return softCrimson
        }

        // 3. Ancestor-chain named colour + lightness boost.
        if let (baseColor, baseDepth) = findNamedColor(for: node, root: root) {
            let depthOffset = max(node.depth - baseDepth, 0)
            let lightnessBoost = Double(depthOffset) * 0.12
            return baseColor.adjustLightness(by: lightnessBoost)
        }

        // 4. Tableau fallback for unmapped paths.
        let ancestor = node.topLevelAncestor(under: root)
        let siblings = root.children
        let index = siblings.firstIndex { $0 == ancestor } ?? 0
        let baseColor = highContrastPalette[index % highContrastPalette.count]
        let depthOffset = max(node.depth - root.depth, 0)
        let darkness = min(Double(depthOffset) * 0.07, 0.35)
        return baseColor.opacity(max(0.92 - darkness, 0.55))
    }

    // MARK: - File-Type palette

    private static func fileTypePaletteColor(for node: FileNode, root: FileNode) -> Color {
        // 1. Hidden → silver (same across schemes).
        if node.name.hasPrefix(".") {
            return Color(red: 0.78, green: 0.80, blue: 0.82)
        }

        // 2. Cache → Soft Crimson.
        if NodeCategory.categorize(node.url) == .cache {
            return softCrimson
        }

        // 3. Generated aggregate nodes → Cool Slate.
        if isGeneratedMisc(node.name) {
            return coolSlate
        }

        // 4. Directories → muted charcoal.
        if node.isDirectory {
            return mutedCharcoal
        }

        // 5. Extension-based category colour.
        return fileTypeColor(for: node)
    }
}
