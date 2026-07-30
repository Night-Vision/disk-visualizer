import SwiftUI
import AppKit

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
    /// under `/Users/<username>/` — e.g. `/Users/ilya/Documents` gets Gold.
    /// Children inside that folder inherit the hue with +12 % lightness per
    /// depth level.
    private static let subfolderColorMap: [String: Color] = [
        "Documents": Color(red: 0.980, green: 0.800, blue: 0.082),  // #FACC15 Electric Gold
        "Downloads": Color(red: 0.984, green: 0.573, blue: 0.235),  // #FB923C Warm Orange
        "Developer": Color(red: 0.176, green: 0.831, blue: 0.749),  // #2DD4BF Teal
        "Pictures":  Color(red: 0.957, green: 0.247, blue: 0.369),  // #F43F5E Rose Pink
        "Movies":    Color(red: 0.882, green: 0.114, blue: 0.282),  // #E11D48 Deep Coral
        "Music":     Color(red: 0.655, green: 0.953, blue: 0.816),  // #A7F3D0 Mint Green
        "Desktop":   Color(red: 0.506, green: 0.549, blue: 0.973),  // #818CF8 Periwinkle
    ]

    // MARK: - Fallback / misc constants

    /// Cool Slate (#64748B) — for aggregated "smaller files"/"other folders" nodes.
    private static let coolSlate   = Color(red: 0.392, green: 0.455, blue: 0.545)

    /// Soft Crimson (#FB7185) — for cache / temp / log paths (replaces the
    /// previous amber hazard, which is now /Library's root colour).
    private static let softCrimson = Color(red: 0.984, green: 0.443, blue: 0.522)

    /// Tableau 10-style high-contrast palette fallback for root-level paths
    /// not matched by any named map (user-scanned subfolders, etc.).
    private static let highContrastPalette: [Color] = [
        Color(red: 0.306, green: 0.475, blue: 0.655), // #4E79A7 bright steel blue
        Color(red: 0.949, green: 0.557, blue: 0.169), // #F28E2B vibrant orange
        Color(red: 0.882, green: 0.341, blue: 0.349), // #E15759 magenta
        Color(red: 0.463, green: 0.718, blue: 0.698), // #76B7B2 teal
        Color(red: 0.349, green: 0.631, blue: 0.310), // #59A14F lime green
        Color(red: 0.929, green: 0.788, blue: 0.282), // #EDC948 bright yellow
        Color(red: 0.690, green: 0.478, blue: 0.631), // #B07AA1 purple
        Color(red: 1.000, green: 0.616, blue: 0.655), // #FF9DA7 pink
        Color(red: 0.612, green: 0.459, blue: 0.373), // #9C755F brown
        Color(red: 0.729, green: 0.690, blue: 0.675), // #BAB0AC grey
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

    /// Look up a named root swatch for a URL by prefix-matching against
    /// `rootColorMap`. Returns `nil` when the path is unmapped.
    private static func rootColor(for url: URL) -> Color? {
        let path = url.path
        return rootColorMap.first { path == $0.prefix || path.hasPrefix($0.prefix + "/") }?.color
    }

    /// Returns `true` when the URL sits inside a user home directory
    /// (path has the form `/Users/<something>/…`).
    private static func isUnderUsers(_ url: URL) -> Bool {
        let comps = url.pathComponents
        return comps.count >= 3 && comps[1] == "Users"
    }

    /// Returns `true` for generated aggregate node names like `[N smaller files]`,
    /// `[other folders]`, and `[deeper items]`.
    private static func isGeneratedMisc(_ name: String) -> Bool {
        if name == "[other folders]" || name == "[deeper items]" { return true }
        return name.hasPrefix("[") && name.hasSuffix(" smaller files]")
    }

    // MARK: - Ancestor-chain color lookup

    /// Walk the ancestor chain from `node` up to the top-level child of `root`,
    /// looking for a named subfolder or misc colour.
    ///
    /// Order:
    ///   1. Misc aggregate names (`[N smaller files]`, …) → Cool Slate
    ///   2. User subfolder names (Documents, Downloads, … under `/Users/…`) → vivid hues
    ///   3. Root path colours (via `rootColor` on the top-level ancestor only)
    ///
    /// Root-path matching uses prefix-based lookup but is **only** checked against
    /// the top-level ancestor URL — never against arbitrary nested nodes, which
    /// would cause `/Users/anything` to match before subfolder names ever fire.
    ///
    /// The caller applies a +12 % lightness boost per depth level between the
    /// matched node and the current node.
    private static func findNamedColor(for node: FileNode, root: FileNode) -> (Color, Int)? {
        // Compute the top-level child of `root` that contains `node`.
        let ancestor = node.topLevelAncestor(under: root)

        // Walk up from `node` to `ancestor` (inclusive), matching misc names
        // and named user subfolders.
        var current: FileNode? = node
        while let c = current {
            let name = c.name

            // 1. Misc aggregate names always match by exact name pattern.
            if isGeneratedMisc(name) {
                return (coolSlate, c.depth)
            }

            // 2. Named user subfolders under /Users/<user>/.
            if isUnderUsers(c.url), let color = subfolderColorMap[name] {
                return (color, c.depth)
            }

            if c == ancestor { break }
            current = c.parent
        }

        // 3. No subfolder/misc match → use the ancestor's root colour
        //    (prefix-based, so /Library/… matches /Library, etc.).
        if let color = rootColor(for: ancestor.url) {
            return (color, ancestor.depth)
        }

        return nil
    }

    // MARK: - Public palette entry point

    /// Determine the display colour for a node in the sunburst or its legend.
    ///
    /// Precedence:
    ///   1. Hidden files (`.`-prefixed) → silver.
    ///   2. Cache / temp / log paths → Soft Crimson (#FB7185).
    ///   3. Ancestor-chain named colour → base hue + lightness boost (+12 %
    ///      per depth level from the matched ancestor).
    ///   4. Everything else → Tableau fallback palette with opacity darkening.
    static func paletteColor(for node: FileNode, root: FileNode) -> Color {
        // 1. Hidden → silver.
        if node.name.hasPrefix(".") {
            return Color(red: 0.78, green: 0.80, blue: 0.82)
        }

        // 2. Cache / temp / log → Soft Crimson.
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
}
