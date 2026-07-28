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
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

                if node != path.last {
                    Text("›")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
