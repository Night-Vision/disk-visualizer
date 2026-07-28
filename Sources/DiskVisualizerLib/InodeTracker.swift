struct InodeKey: Hashable {
    let device: UInt64
    let inode: UInt64
}

/// Tracks inodes within a single scan so hard-linked files are only counted once.
actor InodeTracker {
    private var seen = Set<InodeKey>()

    /// Marks an inode as seen. Returns `true` if this is the first time.
    func mark(inode: UInt64, device: UInt64) -> Bool {
        let key = InodeKey(device: device, inode: inode)
        return seen.insert(key).inserted
    }
}
