import XCTest
@testable import DiskVisualizerLib

final class DiskVisualizerTests: XCTestCase {
    func testSunburstSegments() {
        let store = NodeStore()
        let root = FileNode(url: URL(fileURLWithPath: "/tmp"), isDirectory: true, store: store)
        let a = FileNode(url: URL(fileURLWithPath: "/tmp/a"), isDirectory: false, parent: root, store: store)
        a.size = 100
        let b = FileNode(url: URL(fileURLWithPath: "/tmp/b"), isDirectory: false, parent: root, store: store)
        b.size = 300
        root.children = [a, b]
        root.size = 400

        let segments = SunburstLayout.segments(root: root)

        // Two child segments, each taking its proportional slice.
        XCTAssertEqual(segments.count, 2)
        let first = segments.first { $0.node == a }!
        let second = segments.first { $0.node == b }!
        XCTAssertEqual(first.endAngle - first.startAngle, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(second.endAngle - second.startAngle, .pi * 1.5, accuracy: 0.001)
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
        let root = FileNode(url: URL(fileURLWithPath: "/tmp/cache"), isDirectory: true, store: store)
        let child = FileNode(url: URL(fileURLWithPath: "/tmp/cache/child.txt"), isDirectory: false, parent: root, store: store)
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
