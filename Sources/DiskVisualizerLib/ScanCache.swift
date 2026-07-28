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

    /// Serialize the flat node array to JSON on disk.
    public static func save(store: NodeStore, for url: URL) throws {
        // Skip JSON caching for massive trees (> 50,000 nodes).
        guard store.count <= 50_000 else { return }
        let data = try JSONEncoder().encode(store.nodes)
        try data.write(to: cacheURL(for: url))
    }

    /// Deserialize a flat node array from disk and wrap it in a fresh
    /// `NodeStore`. Returns `nil` when no valid cache exists.
    public static func load(for url: URL) -> NodeStore? {
        let fileURL = cacheURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        guard let nodes = try? JSONDecoder().decode([CompactNode].self, from: data) else { return nil }
        let store = NodeStore()
        store.nodes = nodes
        return store
    }

    public static func invalidate(for url: URL) {
        try? FileManager.default.removeItem(at: cacheURL(for: url))
    }
}
