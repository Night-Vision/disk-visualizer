import Foundation
import os

/// Tracks files within a single scan so hard-linked files are only counted once.
/// Uses `URLResourceValues.fileResourceIdentifier` (identical across hard links
/// to the same inode, unique within a volume) combined with the volume
/// identifier — no extra stat syscall needed; the values come from the
/// resource fetch the scanner already performs.
final class InodeTracker: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<FileIdentity>())

    /// Marks a file as seen. Returns `true` if this is the first time.
    /// Unidentifiable files (either identifier missing) can't be deduplicated
    /// and always count as first.
    func mark(
        file: (any NSObjectProtocol & NSCopying & NSSecureCoding)?,
        volume: (any NSObjectProtocol & NSCopying & NSSecureCoding)?
    ) -> Bool {
        lock.withLock { state in
            guard let file = file as? NSObject,
                  let volume = volume as? NSObject else { return true }
            return state.insert(FileIdentity(file: AnyHashable(file), volume: AnyHashable(volume))).inserted
        }
    }
}

struct FileIdentity: Hashable {
    let file: AnyHashable
    let volume: AnyHashable
}
