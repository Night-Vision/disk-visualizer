import Foundation

/// A single wedge in the sunburst.
struct SunburstSegment: Identifiable {
    let id = UUID()
    let node: FileNode
    let depth: Int
    let startAngle: Double
    let endAngle: Double
}

enum SunburstLayout {
    static let maxDepth = 8
    static let centerHoleRadius: CGFloat = 44
    static let ringGap: CGFloat = 1.0

    /// Build the list of segments for `root`.
    /// Depth 0 is the root; children live at depth >= 1.
    static func segments(root: FileNode, scheme: ColorSchemeMode = .named) -> [SunburstSegment] {
        var segments: [SunburstSegment] = []
        addSegments(node: root, depth: 0, start: 0, end: .pi * 2, scheme: scheme, segments: &segments)
        return segments
    }

    private static func addSegments(
        node: FileNode,
        depth: Int,
        start: Double,
        end: Double,
        scheme: ColorSchemeMode,
        segments: inout [SunburstSegment]
    ) {
        var children = node.children
        guard !children.isEmpty else { return }

        if scheme == .fileType {
            children.sort(by: FileTypeCategory.isOrderedBefore)
        }

        let total = max(children.reduce(0) { $0 + $1.size }, 1)
        var current = start

        for child in children {
            let fraction = Double(child.size) / Double(total)
            let slice = (end - start) * fraction
            let segment = SunburstSegment(
                node: child,
                depth: depth + 1,
                startAngle: current,
                endAngle: current + slice
            )
            segments.append(segment)

            if child.isDirectory && depth + 1 < maxDepth {
                addSegments(
                    node: child,
                    depth: depth + 1,
                    start: current,
                    end: current + slice,
                    scheme: scheme,
                    segments: &segments
                )
            }

            current += slice
        }
    }
}
