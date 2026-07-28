import SwiftUI

extension Color {
    /// Tableau 10-style high-contrast palette. These colors stay legible on
    /// the dark window background and give adjacent top-level folders enough
    /// contrast to be told apart without relying on fine hue discrimination.
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
        Color(red: 0.729, green: 0.690, blue: 0.675)  // #BAB0AC grey
    ]

    /// Generate a distinct, high-contrast palette color for a node within a sunburst.
    /// Top-level folders cycle through the fixed Tableau palette, so adjacent
    /// siblings are easy to distinguish. Deeper children inherit a slightly
    /// darker/less saturated variant of their ancestor's color.
    /// Hidden files/folders (names starting with '.') are rendered in silver.
    static func paletteColor(for node: FileNode, root: FileNode) -> Color {
        if node.name.hasPrefix(".") {
            // Silver: a light, slightly blue-tinted metallic gray.
            return Color(red: 0.78, green: 0.80, blue: 0.82)
        }

        let ancestor = node.topLevelAncestor(under: root)
        let siblings = root.children
        let index = siblings.firstIndex { $0 == ancestor } ?? 0

        let baseColor = highContrastPalette[index % highContrastPalette.count]
        let depthOffset = max(node.depth - root.depth, 0)

        // For deeper rings, gradually darken and desaturate so children stay
        // related to their parent but remain readable against the dark bg.
        let darkness = min(Double(depthOffset) * 0.07, 0.35)
        return baseColor.opacity(max(0.92 - darkness, 0.55))
    }
}
