import Foundation

public enum ScanCache {
    private static var cacheDirectory: URL {
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DiskVisualizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func cacheURL(for url: URL) -> URL {
        let key = url.path
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
        return cacheDirectory.appendingPathComponent("\(key).json")
    }

    private struct CacheEnvelope: Codable {
        // Bumped to 2: caches written before packages and ~/Library were
        // sized correctly hold wrong totals, and `load` rejects them on this
        // mismatch.
        static let currentVersion = 2
        let version: Int
        let nodes: [CompactNode]
    }

    /// Serialize the flat node array wrapped in a versioned envelope to JSON on disk.
    ///
    /// ponytail: JSON, measured — a binary plist of the same 38.8k-node tree is
    /// smaller on disk (27 MB vs 32 MB) but decodes in 0.94 s against JSON's
    /// 0.40 s. If the file size ever matters more than the load, drop the
    /// per-node `url` from the encoded form; it is derivable from
    /// `parentIndex` + `name`.
    public static func save(store: NodeStore, for url: URL) throws {
        // Skip caching for massive trees. Full coverage of `/` measures 38.8k
        // nodes on a 178 GB drive — uncomfortably close to the old 50,000 cap,
        // and going over it silently means a cold walk on every launch.
        guard store.count <= 250_000 else { return }
        let envelope = CacheEnvelope(version: CacheEnvelope.currentVersion, nodes: store.nodes)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: cacheURL(for: url))
    }

    /// Deserialize a flat node array from disk and wrap it in a fresh
    /// `NodeStore`. Returns `nil` when no valid cache exists or schema version mismatches.
    public static func load(for url: URL) -> NodeStore? {
        let fileURL = cacheURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        guard let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              envelope.version == CacheEnvelope.currentVersion else {
            return nil
        }
        let store = NodeStore()
        store.nodes = envelope.nodes
        return store
    }

    public static func invalidate(for url: URL) {
        try? FileManager.default.removeItem(at: cacheURL(for: url))
    }
}
