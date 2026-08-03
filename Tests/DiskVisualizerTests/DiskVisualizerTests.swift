import XCTest
@testable import DiskVisualizerLib

final class DiskVisualizerTests: XCTestCase {
    func testSunburstSegments() {
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
        XCTAssertEqual(store.nodes[0].childIndices[0], b.index)

        let segments = SunburstLayout.segments(root: root)

        // Two child segments, each taking its proportional slice.
        XCTAssertEqual(segments.count, 2)
        let first = segments.first { $0.node == a }!
        let second = segments.first { $0.node == b }!
        XCTAssertEqual(first.endAngle - first.startAngle, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(second.endAngle - second.startAngle, .pi * 1.5, accuracy: 0.001)
    }

    func testRemoveFromTreeReSortsAncestors() {
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
        XCTAssertEqual(store.nodes[c.index].size, 0)
        XCTAssertEqual(store.nodes[b.index].childIndices, [])
        XCTAssertEqual(store.nodes[b.index].size, 20)
        XCTAssertEqual(store.nodes[a.index].size, 60)
        XCTAssertEqual(store.nodes[root.index].size, 130)
        // Multi-level re-sort: E(40) before B(20), D(70) before A(60).
        XCTAssertEqual(store.nodes[a.index].childIndices, [e.index, b.index])
        XCTAssertEqual(store.nodes[root.index].childIndices, [d.index, a.index])
        // Idempotent: trashing the (now-zeroed) node again is a no-op.
        c.removeFromTree()
        XCTAssertEqual(store.nodes[root.index].size, 130)
    }

    func testInodeTrackerMarksFirstOnly() async {
        let tracker = InodeTracker()
        let first = tracker.mark(file: NSNumber(value: 123), volume: NSNumber(value: 1))
        let second = tracker.mark(file: NSNumber(value: 123), volume: NSNumber(value: 1))
        let different = tracker.mark(file: NSNumber(value: 124), volume: NSNumber(value: 1))

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertTrue(different)
    }

    func testScanCacheRoundTrip() throws {
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

        XCTAssertNotNil(loadedStore)
        XCTAssertEqual(loadedStore?.nodes[0].size, 42)
        XCTAssertEqual(loadedStore?.nodes[0].childIndices.count, 1)
        XCTAssertEqual(loadedStore?.nodes[1].size, 42)

        ScanCache.invalidate(for: url)
    }
}
