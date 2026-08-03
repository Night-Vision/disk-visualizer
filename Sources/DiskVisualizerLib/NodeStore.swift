import Foundation

/// One node in the flat scan tree. All node data lives here; `FileNode` is a
/// lightweight struct wrapping a `(NodeStore, Int)` pair.
public struct CompactNode: Codable {
    public var name: String
    public var url: URL
    public var isDirectory: Bool
    public var size: Int64
    public var parentIndex: Int            // -1 for root
    public var childIndices: [Int]
    public var isScanned: Bool
    public var modificationDate: Date?
}

/// Flat-array backing store for a scan tree. `nodes` is append-only — no
/// reordering or deletion (trash zeroes `size` but keeps the slot).
/// Writes during parallel scanning are guarded by NSLock; reads after the
/// scan completes (or from the main thread) are lock-free.
public final class NodeStore: @unchecked Sendable {
    public internal(set) var nodes: [CompactNode] = []
    private let lock = NSLock()
    /// Set on the MainActor once the scan task has finished writing. After
    /// this, all readers are MainActor and the flag write (inside the same
    /// `MainActor.run` hop that flips `isScanning`) orders every scan write
    /// before any later read, so `read` can skip the lock.
    private var scanCompleted = false

    public var count: Int { nodes.count }

    /// Thread-safe read of a single node at `index`. Locks only while the
    /// parallel scan is still writing (the breadcrumb header reads the root
    /// chain concurrently during the scan window); lock-free once complete.
    func read<T>(at index: Int, _ access: (CompactNode) -> T) -> T {
        if scanCompleted { return access(nodes[index]) }
        return lock.withLock { access(nodes[index]) }
    }

    /// Mark the store as fully written. Must be called from the MainActor
    /// after the scan task's last write, so the flag write orders all scan
    /// writes-before any later read.
    func markScanComplete() {
        scanCompleted = true
    }

    /// Thread-safe append. Returns the index of the newly inserted node.
    @discardableResult
    func append(_ node: CompactNode) -> Int {
        lock.withLock {
            let idx = nodes.count
            nodes.append(node)
            return idx
        }
    }

    // MARK: - Tree walking

    /// Depth of the node at `index` (0 for root, 1 for its children, …).
    func depth(of index: Int) -> Int {
        var current = index
        var d = 0
        while true {
            let p = nodes[current].parentIndex
            guard p >= 0 else { return d }
            current = p
            d += 1
        }
    }

    /// The immediate child of `rootIndex` that contains the node at `index`.
    func topLevelAncestor(of index: Int, under rootIndex: Int) -> Int {
        var current = index
        while true {
            let p = nodes[current].parentIndex
            guard p >= 0, p != rootIndex else { return current }
            current = p
        }
    }

    /// Breadcrumb path: root-first chain from the node at `index` to the tree root.
    func path(from index: Int) -> [Int] {
        var chain: [Int] = []
        var current: Int = index
        while true {
            chain.append(current)
            let p = nodes[current].parentIndex
            guard p >= 0 else { break }
            current = p
        }
        return chain.reversed()
    }

    /// Returns true when `ancestorIndex` is reachable by walking parent pointers
    /// from `childIndex`.
    func isAncestor(_ ancestorIndex: Int, of childIndex: Int) -> Bool {
        var current = nodes[childIndex].parentIndex
        while current >= 0 {
            if current == ancestorIndex { return true }
            current = nodes[current].parentIndex
        }
        return false
    }

    /// Children of the node at `index`, as flat-array indices.
    func children(of index: Int) -> [Int] {
        nodes[index].childIndices
    }

    /// Total number of nodes in the subtree rooted at `index` (inclusive).
    func totalNodeCount(from index: Int) -> Int {
        var count = 1
        for child in nodes[index].childIndices {
            count += totalNodeCount(from: child)
        }
        return count
    }

    // MARK: - Mutation

    /// Remove the node at `index` from its parent's child list and subtract
    /// its size from all ancestors. Idempotent: after the first call `size` is
    /// zeroed so subsequent calls are no-ops. Thread-safe.
    ///
    /// Also maintains the size-descending order of `childIndices` established
    /// at scan time: each node whose size shrank may now be out of order among
    /// its siblings, so every ancestor's parent's child list is re-sorted.
    func removeFromTree(_ index: Int) {
        lock.withLock {
            let pi = nodes[index].parentIndex
            guard pi >= 0 else { return }
            nodes[pi].childIndices.removeAll { $0 == index }
            let removedSize = nodes[index].size
            nodes[index].size = 0
            guard removedSize > 0 else { return }
            var current = pi
            while current >= 0 {
                nodes[current].size -= removedSize
                // This node's size changed, so it may be out of order among its
                // own parent's children. Restore the size-descending invariant.
                let parent = nodes[current].parentIndex
                if parent >= 0 {
                    // Sort a local copy, not the stored array: an in-place sort
                    // of `nodes[parent].childIndices` while the predicate reads
                    // `nodes[$0]` trips Swift's exclusivity checker (same array
                    // storage, unproven-disjoint indices) and aborts.
                    var children = nodes[parent].childIndices
                    children.sort { nodes[$0].size > nodes[$1].size }
                    nodes[parent].childIndices = children
                }
                current = parent
            }
        }
    }

    /// Set the child list for the node at `index`. Thread-safe.
    ///
    /// Sorts size-descending so the ordering invariant holds for every caller —
    /// the scanner, tests, and any future mutation path — without each call site
    /// remembering to sort. `removeFromTree` re-sorts inline instead (it already
    /// holds the lock; this method would deadlock on the non-recursive NSLock).
    func setChildren(_ children: [Int], for index: Int) {
        lock.withLock {
            var sorted = children
            sorted.sort { nodes[$0].size > nodes[$1].size }
            nodes[index].childIndices = sorted
        }
    }

    /// Set the size for the node at `index`. Thread-safe.
    func setSize(_ size: Int64, for index: Int) {
        lock.withLock { nodes[index].size = size }
    }

    /// Set the scanned flag for the node at `index`. Thread-safe.
    func setScanned(_ scanned: Bool, for index: Int) {
        lock.withLock { nodes[index].isScanned = scanned }
    }

    /// Set the modification date for the node at `index`. Thread-safe.
    func setModificationDate(_ date: Date?, for index: Int) {
        lock.withLock { nodes[index].modificationDate = date }
    }

    // MARK: - Formatting helpers

    func formattedSize(of index: Int) -> String {
        ByteCountFormatter.string(fromByteCount: nodes[index].size, countStyle: .file)
    }

    func iconName(of index: Int) -> String {
        let node = nodes[index]
        if node.isDirectory { return "folder.fill" }
        switch node.url.pathExtension.lowercased() {
        case "":      return "doc"
        case "txt", "md", "log", "csv": return "doc.text"
        case "swift": return "swift"
        case "json", "yaml", "yml", "xml", "toml": return "curlybraces"
        case "html", "htm": return "globe"
        case "png", "jpg", "jpeg", "gif", "svg", "heic", "webp": return "photo"
        case "mov", "mp4", "qt", "avi", "mkv": return "film"
        case "mp3", "wav", "aac", "flac", "m4a": return "music.note"
        case "pdf":   return "doc.richtext"
        case "zip", "tar", "gz", "7z", "rar", "dmg": return "archivebox"
        case "app":   return "app.fill"
        case "sh", "bash", "zsh", "fish": return "terminal"
        default:      return "doc"
        }
    }

    func childSummary(of index: Int) -> String {
        let node = nodes[index]
        if !node.isDirectory { return "—" }
        let count = node.childIndices.count
        let hasOverflow = node.childIndices.contains { nodes[$0].name == "[other folders]" }
        let suffix = count == 1 ? "item" : "items"
        return hasOverflow ? "\(count)+ \(suffix)" : "\(count) \(suffix)"
    }

    func formattedModificationDate(of index: Int) -> String {
        guard let date = nodes[index].modificationDate else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
