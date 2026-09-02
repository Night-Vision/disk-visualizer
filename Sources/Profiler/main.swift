import Foundation
import Darwin
import DiskVisualizerLib

/// Format a byte count for human reading.
private func fmtBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

@main
struct Profiler {
    static func main() async throws {
        let args = CommandLine.arguments.dropFirst()
        // --cached measures the warm-launch path (cache hit) instead of a walk.
        let useCache = args.contains("--cached")
        let path = args.first { !$0.hasPrefix("--") } ?? "/Users/ilyaashirov"
        let url = URL(fileURLWithPath: path)

        print("Profiling scan of: \(url.path)")
        print(useCache ? "Using on-disk cache if present" : "Ignoring on-disk cache")

        let scanner = DiskScanner()
        let start = DispatchTime.now()
        scanner.scan(url: url, ignoreCache: !useCache)

        while scanner.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0

        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let peakRSS = usage.ru_maxrss

        let nodeCount = scanner.rootNode?.totalNodeCount ?? 0

        print("\n=== Profiler Results ===")
        print("Path: \(url.path)")
        print("Scan elapsed: \(String(format: "%.3f", elapsed)) s")
        print("Peak RSS: \(peakRSS) bytes (\(fmtBytes(Int64(peakRSS))))")
        print("Nodes in tree: \(nodeCount)")
        print("Scanned bytes: \(fmtBytes(scanner.scannedBytes))")
        print("Scanned items: \(scanner.scannedItemCount)")
        if let errorMessage = scanner.errorMessage {
            print("Error: \(errorMessage)")
        }
        print("Needs Full Disk Access: \(scanner.requiresFullDiskAccess)")

        if let root = scanner.rootNode {
            print("Root total: \(fmtBytes(root.size))")
            if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
               let total = values.volumeTotalCapacity,
               let available = values.volumeAvailableCapacity {
                let used = Int64(total - available)
                let coverage = Double(root.size) / Double(max(used, 1)) * 100
                print("Volume used: \(fmtBytes(used))   coverage: \(String(format: "%.1f", coverage))%")
            }
            print("--- top-level ---")
            for child in root.children.prefix(25) {
                let name = child.name.padding(toLength: 30, withPad: " ", startingAt: 0)
                print("  \(name) \(fmtBytes(child.size))")
            }
        }
        print("========================")
    }
}
