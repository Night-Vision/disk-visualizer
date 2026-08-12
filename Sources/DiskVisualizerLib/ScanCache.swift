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
        static let currentVersion = 1
        let version: Int
        let nodes: [CompactNode]
    }

    /// Serialize the flat node array wrapped in a versioned envelope to JSON on disk.
    public static func save(store: NodeStore, for url: URL) throws {
        // Skip JSON caching for massive trees (> 50,000 nodes).
        guard store.count <= 50_000 else { return }
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
