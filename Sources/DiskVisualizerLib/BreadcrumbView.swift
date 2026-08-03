import SwiftUI

struct BreadcrumbView: View {
    let currentRoot: FileNode?
    let appRoot: FileNode?
    let onSelect: (FileNode?) -> Void

    private var path: [FileNode] {
        let start = currentRoot ?? appRoot
        var nodes: [FileNode] = []
        var node: FileNode? = start
        while let n = node {
            nodes.append(n)
            node = n.parent
        }
        return nodes.reversed()
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(path) { node in
                Button(node.name) {
                    onSelect(node == appRoot ? nil : node)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                // The last crumb is the current location — clicking it is a
                // no-op, so gray it out as a native "you are here" cue.
                .disabled(node == path.last)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(node == path.last ? .secondary : .primary)

                if node != path.last {
                    Text("›")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
