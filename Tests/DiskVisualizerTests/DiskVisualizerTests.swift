import Foundation
import Testing
@testable import DiskVisualizerLib

@Suite struct DiskVisualizerTests {
    @Test func sunburstSegments() {
        let store = NodeStore()
        var root = FileNode(url: URL(fileURLWithPath: "/tmp"), isDirectory: true, store: store)
        var a = FileNode(url: URL(fileURLWithPath: "/tmp/a"), isDirectory: false, parent: root, store: store)
        a.size = 100
        var b = FileNode(url: URL(fileURLWithPath: "/tmp/b"), isDirectory: false, parent: root, store: store)
        b.size = 300
        root.children = [a, b]
        root.size = 400

        // Size-descending order is enforced at the store write boundary:
        // b (300) must come before a (100) despite insertion order.
        #expect(store.nodes[0].childIndices[0] == b.index)

        let segments = SunburstLayout.segments(root: root)

        // Two child segments, each taking its proportional slice.
        #expect(segments.count == 2)
        let first = segments.first { $0.node == a }!
        let second = segments.first { $0.node == b }!
        #expect(abs((first.endAngle - first.startAngle) - .pi / 2) < 0.001)
        #expect(abs((second.endAngle - second.startAngle) - .pi * 1.5) < 0.001)
    }

    @Test func removeFromTreeReSortsAncestors() {
        let store = NodeStore()
        var root = FileNode(url: URL(fileURLWithPath: "/tmp/r"), isDirectory: true, store: store)
        var a = FileNode(url: URL(fileURLWithPath: "/tmp/r/a"), isDirectory: true, parent: root, store: store)
        a.size = 100
        var d = FileNode(url: URL(fileURLWithPath: "/tmp/r/d"), isDirectory: true, parent: root, store: store)
        d.size = 70
        var b = FileNode(url: URL(fileURLWithPath: "/tmp/r/a/b"), isDirectory: true, parent: a, store: store)
        b.size = 60
        var e = FileNode(url: URL(fileURLWithPath: "/tmp/r/a/e"), isDirectory: true, parent: a, store: store)
        e.size = 40
        var c = FileNode(url: URL(fileURLWithPath: "/tmp/r/a/b/c"), isDirectory: false, parent: b, store: store)
        c.size = 40

        root.children = [a, d]
        a.children = [b, e]
        b.children = [c]
        root.size = 170

        c.removeFromTree()

        // C zeroed and removed from B; sizes subtracted up the chain.
        #expect(store.nodes[c.index].size == 0)
        #expect(store.nodes[b.index].childIndices == [])
        #expect(store.nodes[b.index].size == 20)
        #expect(store.nodes[a.index].size == 60)
        #expect(store.nodes[root.index].size == 130)
        // Multi-level re-sort: E(40) before B(20), D(70) before A(60).
        #expect(store.nodes[a.index].childIndices == [e.index, b.index])
        #expect(store.nodes[root.index].childIndices == [d.index, a.index])
        // Idempotent: trashing the (now-zeroed) node again is a no-op.
        c.removeFromTree()
        #expect(store.nodes[root.index].size == 130)
    }

    @Test func inodeTrackerMarksFirstOnly() async {
        let tracker = InodeTracker()
        let first = tracker.mark(file: NSNumber(value: 123), volume: NSNumber(value: 1))
        let second = tracker.mark(file: NSNumber(value: 123), volume: NSNumber(value: 1))
        let different = tracker.mark(file: NSNumber(value: 124), volume: NSNumber(value: 1))

        #expect(first)
        #expect(!second)
        #expect(different)
    }

    @Test func scanCacheRoundTrip() throws {
        let store = NodeStore()
        var root = FileNode(url: URL(fileURLWithPath: "/tmp/cache"), isDirectory: true, store: store)
        var child = FileNode(url: URL(fileURLWithPath: "/tmp/cache/child.txt"), isDirectory: false, parent: root, store: store)
        child.size = 42
        root.children = [child]
        root.size = 42

        let url = URL(fileURLWithPath: "/tmp/cache-test")
        ScanCache.invalidate(for: url)

        try ScanCache.save(store: store, for: url)
        let loadedStore = ScanCache.load(for: url)

        #expect(loadedStore != nil)
        #expect(loadedStore?.nodes[0].size == 42)
        #expect(loadedStore?.nodes[0].childIndices.count == 1)
        #expect(loadedStore?.nodes[1].size == 42)

        ScanCache.invalidate(for: url)
    }

    @Test func scanCacheVersionMismatch() throws {
        let url = URL(fileURLWithPath: "/tmp/cache-mismatch-test")
        ScanCache.invalidate(for: url)

        // Write mismatched version JSON directly to cache path
        let key = url.path
            .data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DiskVisualizer", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheURL = cacheDir.appendingPathComponent("\(key).json")

        let invalidPayload = """
        {"version": 999, "nodes": []}
        """.data(using: .utf8)!
        try invalidPayload.write(to: cacheURL)

        let loadedStore = ScanCache.load(for: url)
        #expect(loadedStore == nil)

        ScanCache.invalidate(for: url)
    }

    @Test func fileTypeCategorization() {
        let store = NodeStore()
        let root = FileNode(url: URL(fileURLWithPath: "/Users/test/project"), isDirectory: true, store: store)

        let codeNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/main.swift"), isDirectory: false, parent: root, store: store)
        let binaryNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/App.app"), isDirectory: false, parent: root, store: store)
        let mediaNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/image.png"), isDirectory: false, parent: root, store: store)
        let docNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/notes.pdf"), isDirectory: false, parent: root, store: store)
        let archiveNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/archive.zip"), isDirectory: false, parent: root, store: store)
        let audioNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/song.mp3"), isDirectory: false, parent: root, store: store)
        let systemNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/db.sqlite"), isDirectory: false, parent: root, store: store)
        let folderNode = FileNode(url: URL(fileURLWithPath: "/Users/test/project/Subfolder"), isDirectory: true, parent: root, store: store)

        #expect(FileTypeCategory.categorize(node: codeNode) == .developerCode)
        #expect(FileTypeCategory.categorize(node: binaryNode) == .executablesBinaries)
        #expect(FileTypeCategory.categorize(node: mediaNode) == .media)
        #expect(FileTypeCategory.categorize(node: docNode) == .documentsData)
        #expect(FileTypeCategory.categorize(node: archiveNode) == .archivesPackages)
        #expect(FileTypeCategory.categorize(node: audioNode) == .audioSound)
        #expect(FileTypeCategory.categorize(node: systemNode) == .systemCachesLogs)
        #expect(FileTypeCategory.categorize(node: folderNode) == .unclassifiedFolders)
    }
}

@Suite struct CoverageTests {
    /// A package must be sized by what it contains. Before the fix it fell
    /// through to the file branch and reported its directory inode (~0 bytes),
    /// which is why /Applications showed 61 KB for 19 GB of apps.
    @Test @MainActor func packageIsSizedByItsContents() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resources = tmp.appendingPathComponent("Fake.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: resources.appendingPathComponent("big.bin"))
        defer {
            ScanCache.invalidate(for: tmp)
            try? FileManager.default.removeItem(at: tmp)
        }

        let scanner = DiskScanner()
        scanner.scan(url: tmp, ignoreCache: true)
        while scanner.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let app = try #require(scanner.rootNode?.children.first { $0.name == "Fake.app" })
        #expect(app.size >= 300_000)
        #expect(scanner.rootNode?.size ?? 0 >= 300_000)
    }

    /// Only the genuinely TCC-gated paths are pre-skipped. A blanket
    /// "Library/" rule used to match here and dropped 76 GB of readable data.
    @Test func onlyTCCPathsArePreSkipped() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(!DiskScanner.isProtectedDirectory(home.appendingPathComponent("Library/Application Support")))
        #expect(!DiskScanner.isProtectedDirectory(home.appendingPathComponent("Library/Containers")))
        #expect(!DiskScanner.isProtectedDirectory(home.appendingPathComponent("Library/Caches")))
        #expect(DiskScanner.isProtectedDirectory(home.appendingPathComponent("Library/Messages")))
        #expect(DiskScanner.isProtectedDirectory(home.appendingPathComponent("Library/Mail/V10")))
        #expect(DiskScanner.isProtectedDirectory(home.appendingPathComponent("Pictures")))
    }
}
