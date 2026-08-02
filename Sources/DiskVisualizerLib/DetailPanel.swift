import SwiftUI

struct DetailPanel: View {
    let root: FileNode
    let selected: FileNode?
    var onDelete: (FileNode) -> Void = { _ in }
    var onSelect: (FileNode) -> Void = { _ in }

    @Environment(\.colorSchemeMode) private var colorScheme

    private var displayed: FileNode {
        selected ?? root
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayed.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(displayed.formattedSize)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Move to Trash") {
                    onDelete(displayed)
                }
                .controlSize(.small)
                .disabled(displayed == root)
            }

            Divider()

            List(root.children) { child in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.paletteColor(for: child, root: root, scheme: colorScheme))
                        .frame(width: 12, height: 12)

                    Text(child.name)
                        .lineLimit(1)

                    Spacer()

                    Text(child.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(child) }
            }
            .listStyle(.plain)
        }
        .padding()
        .frame(minWidth: 240)
    }
}
