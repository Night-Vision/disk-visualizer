import Foundation

/// Lightweight struct wrapper around a `(NodeStore, Int)` pair. All data is
/// stored in the flat `CompactNode` array inside `store`; this struct just
/// provides convenient property access and reference semantics for the UI.
///
/// Identity is based on the flat-array `index` — two `FileNode`s are equal
/// when they point to the same store slot.
public struct FileNode: Identifiable, Hashable, Sendable {
    let store: NodeStore
    public let index: Int

    public var id: Int { index }

    // MARK: - Stored (redirected) properties

    public var url: URL { store.nodes[index].url }
    public var name: String { store.nodes[index].name }
    public var isDirectory: Bool { store.nodes[index].isDirectory }

    public var parent: FileNode? {
        let p = store.nodes[index].parentIndex
        guard p >= 0 else { return nil }
        return FileNode(store: store, index: p)
    }

    public var children: [FileNode] {
        get { store.nodes[index].childIndices.map { FileNode(store: store, index: $0) } }
        set { store.setChildren(newValue.map { $0.index }, for: index) }
    }

    public var size: Int64 {
        get { store.nodes[index].size }
        set { store.setSize(newValue, for: index) }
    }

    public var isScanned: Bool {
        get { store.nodes[index].isScanned }
        set { store.setScanned(newValue, for: index) }
    }

    public var modificationDate: Date? {
        get { store.nodes[index].modificationDate }
        set { store.setModificationDate(newValue, for: index) }
    }

    // MARK: - Computed helpers

    public var depth: Int { store.depth(of: index) }
    public var formattedSize: String { store.formattedSize(of: index) }
    public var totalNodeCount: Int { store.totalNodeCount(from: index) }
    public var iconName: String { store.iconName(of: index) }
    public var childSummary: String { store.childSummary(of: index) }
    public var formattedModificationDate: String { store.formattedModificationDate(of: index) }

    // MARK: - Operations

    /// Walk up the tree until we hit the top-level child of `root`.
    func topLevelAncestor(under root: FileNode) -> FileNode {
        let idx = store.topLevelAncestor(of: index, under: root.index)
        return FileNode(store: store, index: idx)
    }

    /// Remove this node from its parent's children and subtract its size from
    /// all ancestors. Idempotent.
    func removeFromTree() {
        store.removeFromTree(index)
    }

    // MARK: - Init

    /// Create a new node by appending a `CompactNode` to the store.
    init(url: URL, isDirectory: Bool = false, parent: FileNode? = nil, store: NodeStore) {
        self.store = store
        let last = url.lastPathComponent
        let name = last.isEmpty ? url.path : last
        self.index = store.append(CompactNode(
            name: name,
            url: url,
            isDirectory: isDirectory,
            size: 0,
            parentIndex: parent?.index ?? -1,
            childIndices: [],
            isScanned: false,
            modificationDate: nil
        ))
    }

    /// Reconstruct a FileNode from an existing store slot (no append).
    init(store: NodeStore, index: Int) {
        self.store = store
        self.index = index
    }

    // MARK: - Hashable / Equatable

    public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.index == rhs.index
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(index)
    }
}
