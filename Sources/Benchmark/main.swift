import Foundation
import Darwin
import DiskVisualizerLib

/// Recursively create `branching` subdirectories at each level, up to
/// `depth` levels, and place one small file in each directory so the
/// scanner exercises both directory and file paths.
private func generateTree(at url: URL, depth: Int, branching: Int) {
    guard depth > 0 else { return }
    for i in 0..<branching {
        let dirURL = url.appendingPathComponent("dir\(i)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fileURL = dirURL.appendingPathComponent("file.txt")
        try? "x".write(to: fileURL, atomically: true, encoding: .utf8)
        generateTree(at: dirURL, depth: depth - 1, branching: branching)
    }
}

/// Format a byte count for human reading.
private func fmtBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

@main
struct Benchmark {
    static func main() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskVisualizerBenchmark-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        generateTree(at: baseURL, depth: 6, branching: 4)

        // MARK: Scan
        let scanner = DiskScanner()
        let start = DispatchTime.now()
        scanner.scan(url: baseURL, ignoreCache: true)
        while scanner.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        }
        let scanElapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0

        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let scanPeakRSS = usage.ru_maxrss

        let nodeCount = scanner.rootNode?.totalNodeCount ?? 0

        // MARK: Flat-array JSON cache save
        let saveStart = DispatchTime.now()
        try? scanner.saveCache(for: baseURL)
        let saveElapsed = Double(DispatchTime.now().uptimeNanoseconds - saveStart.uptimeNanoseconds) / 1_000_000_000.0

        // MARK: Flat-array JSON cache load
        let loadStart = DispatchTime.now()
        let loadedStore = ScanCache.load(for: baseURL)
        let loadElapsed = Double(DispatchTime.now().uptimeNanoseconds - loadStart.uptimeNanoseconds) / 1_000_000_000.0

        let loadedNodeCount = loadedStore?.count ?? 0

        getrusage(RUSAGE_SELF, &usage)
        let finalPeakRSS = usage.ru_maxrss

        print("=== DiskVisualizer Scan Benchmark ===")
        print("Path: \(baseURL.path)")
        print("Nodes: \(nodeCount)")
        print("Scan elapsed: \(String(format: "%.3f", scanElapsed)) s")
        print("Scan peak RSS: \(scanPeakRSS) bytes (\(fmtBytes(Int64(scanPeakRSS))))")
        print("Flat-array JSON cache save elapsed: \(String(format: "%.3f", saveElapsed)) s")
        print("Flat-array JSON cache load elapsed: \(String(format: "%.3f", loadElapsed)) s")
        print("Loaded node count: \(loadedNodeCount)")
        print("Final peak RSS: \(finalPeakRSS) bytes (\(fmtBytes(Int64(finalPeakRSS))))")
        print("======================================")

        // Clean up the cache file we created for this run.
        ScanCache.invalidate(for: baseURL)
    }
}
