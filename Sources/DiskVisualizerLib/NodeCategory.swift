import Foundation

/// Visual classification for a FileNode, driving the diagonal-hatch rendering
/// style in `SunburstView.drawSegment`.
///
/// Categories are mutually exclusive — cache wins over system wins over regular,
/// because cache zones (~/Library/Caches, /private/tmp, …) are drawn yellow/black
/// hazard tape so they pop against system-zone B/W stripes.
enum NodeCategory {
    case regular
    case system
    case cache

    /// Cached user home path. `homeDirectoryForCurrentUser` doesn't change
    /// during a session, so we capture it once. `static let` is fine here:
    /// Swift guarantees thread-safe lazy init for static let bindings and
    /// there's no later assignment. Reads on the `cachedHomeCacheRoots`
    /// initializer below therefore use the same value the
    /// `categorize(_:)` callers see.
    /// MUST be declared before `cachedHomeCacheRoots` so Swift's
    /// declaration-order static initialization produces a populated
    /// home path; declaring after would silently produce empty-prefix
    /// roots like `"" + "/Library/Caches"`.
    private static let _cachedHomePath: String = FileManager.default.homeDirectoryForCurrentUser.path

    /// Classify a single `url` against the canonical macOS helper paths.
    /// Computed synchronously, no I/O — safe to call inside the sunburst's
    /// hot redraw loop. Walks the cache-then-system precedence chain.
    static func categorize(_ url: URL) -> NodeCategory {
        let path = url.path

        // 1. Cache wins. A node is treated as cache-cleanup territory if its
        //    absolute path matches one of these roots exactly or sits under it.
        if isCachePath(path) { return .cache }

        // 2. System wins over regular. Top-of-tree macOS hierarchy directories
        //    that the user shouldn't be editing casually — sunburst draws them
        //    with black/white diagonal hatching so they read as "operator zone".
        if isSystemPath(path) { return .system }

        return .regular
    }

    // MARK: - Cache-root detection

    private static func isCachePath(_ path: String) -> Bool {
        for root in absoluteCacheRoots where path == root || path.hasPrefix(root + "/") {
            return true
        }
        for root in cachedHomeCacheRoots
            where path == root || path.hasPrefix(root + "/") {
            return true
        }
        return false
    }

    /// System-wide cache roots. `confstr(_CS_DARWIN_USER_TEMP_DIR)` returns
    /// `/var/folders/<a-b>/<c>/T/` on macOS, so `/private/var/folders/*` is
    /// the canonical parent for user-specific temp+cache.
    private static let absoluteCacheRoots: [String] = [
        "/Library/Caches",
        "/System/Library/Caches",
        "/private/var/folders",     // per-user temp, the modern Darwin temp dir
        "/private/tmp",             // legacy /tmp (still used by many CLIs)
        "/tmp",                     // symlink-resolved equivalent of /private/tmp
        "/private/var/tmp"          // legacy /var/tmp
    ]

    /// User-home cache roots, baked once at first classify call. Without this
    /// memoization, `isCachePath` would allocate a fresh 5-element `[String]`
    /// on every FileNode × every redraw — hundreds of allocs per second during
    /// pan/zoom. With this `static let`, the array is built exactly once.
    private static let cachedHomeCacheRoots: [String] = [
        _cachedHomePath + "/Library/Caches",
        _cachedHomePath + "/Library/Logs",
        _cachedHomePath + "/Library/Application Support/CrashReporter",
        _cachedHomePath + "/Library/Developer/CoreSimulator/Caches",
        _cachedHomePath + "/Library/Developer/Xcode/DerivedData"
    ]

    // MARK: - System-path detection

    private static func isSystemPath(_ path: String) -> Bool {
        if systemTopLevel.contains(path) { return true }
        for root in systemTopLevel where path.hasPrefix(root + "/") { return true }
        return false
    }

    /// Top-level POSIX hierarchy folders that ship as part of macOS. The
    /// user's ~/Library is *not* here — it's under `_cachedHomePath` and
    /// gets the regular palette + its cache subtrees get the hazard hatch
    /// from the cache rule.
    private static let systemTopLevel: [String] = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/opt",
        "/private",
        "/dev",
        "/var",
        "/cores"
    ]
}
