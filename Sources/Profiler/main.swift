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
        let path = CommandLine.arguments.dropFirst().first ?? "/Users/ilyaashirov"
        let url = URL(fileURLWithPath: path)

        print("Profiling scan of: \(url.path)")
        print("Ignoring on-disk cache")

        let scanner = DiskScanner()
        let start = DispatchTime.now()
        scanner.scan(url: url, ignoreCache: true)

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
        print("========================")
    }
}
