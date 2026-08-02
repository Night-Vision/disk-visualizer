import Foundation

/// Throttled progress reporter that batches updates and flushes them on the main actor.
actor ScanProgress {
    private var pendingBytes: Int64 = 0
    private var pendingItems: Int = 0
    private var lastFlush = Date()
    private let onUpdate: @Sendable (Int64, Int) -> Void

    init(onUpdate: @escaping @Sendable (Int64, Int) -> Void) {
        self.onUpdate = onUpdate
    }

    func add(bytes: Int64 = 0, items: Int = 0) {
        pendingBytes += bytes
        pendingItems += items
        if Date().timeIntervalSince(lastFlush) >= 0.1 {
            flush()
        }
    }

    func flush() {
        guard pendingItems > 0 || pendingBytes > 0 else { return }
        onUpdate(pendingBytes, pendingItems)
        pendingBytes = 0
        pendingItems = 0
        lastFlush = Date()
    }
}

@Observable
public final class DiskScanner {
    public init() {}

    /// Flat-array store for the scan tree. Public only for cache save/load.
    public private(set) var store = NodeStore()
    /// Index of the root node in `store`, or `nil` when no scan has completed.
    public private(set) var rootIndex: Int?

    /// The root node of the last completed scan, or `nil`.
    public var rootNode: FileNode? {
        rootIndex.map { FileNode(store: store, index: $0) }
    }

    public var isScanning = false
    var isCancelling = false
    public var scannedBytes: Int64 = 0
    public var scannedItemCount: Int = 0
    public var errorMessage: String?
    public var requiresFullDiskAccess = false

    private var scanTask: Task<Void, Never>?

    /// Cache the last scan result to disk for the given URL.
    public func saveCache(for url: URL) throws {
        try ScanCache.save(store: store, for: url)
    }

    public func scan(url: URL, ignoreCache: Bool = false) {
        cancel()
        isScanning = true
        isCancelling = false
        errorMessage = nil
        requiresFullDiskAccess = false
        rootIndex = nil
        scannedBytes = 0
        scannedItemCount = 0

        // Fresh store for this scan.
        store = NodeStore()

        scanTask = Task {
            await Task.yield()

            do {
                let root = FileNode(url: url, isDirectory: true, store: store)
                rootIndex = root.index

                let tracker = InodeTracker()
                let permissionCounter = PermissionErrorCounter()
                let hasFDA = Self.hasFullDiskAccess
                let progress = ScanProgress { [weak self] bytes, items in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.scannedBytes += bytes
                        self.scannedItemCount += items
                    }
                }

                try await Self.scan(
                    node: root,
                    depth: 0,
                    hasFDA: hasFDA,
                    tracker: tracker,
                    permissionCounter: permissionCounter,
                    progress: progress
                )
                await progress.flush()

                let hasErrors = await permissionCounter.hasErrors
                let needsFDA = !hasFDA && hasErrors
                try? saveCache(for: url)

                await MainActor.run {
                    // Same hop that flips `isScanning` — the flag write
                    // happens-before every subsequent (MainActor) read, so
                    // `NodeStore.read` can go lock-free from here on.
                    self.store.markScanComplete()
                    self.requiresFullDiskAccess = needsFDA
                    self.isScanning = false
                    self.isCancelling = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isScanning = false
                    self.isCancelling = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isScanning = false
                    self.isCancelling = false
                }
            }
        }
    }

    public func cancel() {
        scanTask?.cancel()
        isCancelling = true
    }

    // MARK: - Scan constants

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .linkCountKey,
        .contentModificationDateKey,
        .fileResourceIdentifierKey,
        .volumeIdentifierKey
    ]

    private static let resourceKeysSet = Set(resourceKeys)
    private static let maxConcurrentScans = 16
    private static let maxChildrenPerNode = 50
    private static let maxDepth = SunburstLayout.maxDepth

    private static let shallowScanPaths: Set<String> = ["/System", "/Library", "/private", "/opt", "/dev"]
    private static let skipDirectoryNames: Set<String> = [".noflow", ".nofollow"]

    private static let skipRootPaths: Set<String> = [
        "/Volumes",
        "/System/Volumes",
        "/home",
        "/net",
        "/Network"
    ]

    private static let skipRootHiddenPrefixes: Set<String> = [".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".vol"]

    private static func shouldSkip(_ url: URL) -> Bool {
        if url.path == "/" { return false }
        let path = url.path
        for skipRoot in skipRootPaths {
            if path == skipRoot || path.hasPrefix(skipRoot + "/") { return true }
        }
        // System hidden dirs (.Spotlight-V100, .fseventsd, …) can sit at the
        // root of any volume. Match by last path component — absolute prefix
        // matching would only catch them at the boot-volume root.
        if skipRootHiddenPrefixes.contains(url.lastPathComponent) {
            return true
        }
        return false
    }

    private static func shouldShallowScan(url: URL) -> Bool {
        shallowScanPaths.contains(url.path)
    }

    // MARK: - Recursive scan

    private static func scan(
        node: FileNode,
        depth: Int,
        hasFDA: Bool,
        tracker: InodeTracker,
        permissionCounter: PermissionErrorCounter,
        progress: ScanProgress
    ) async throws {
        // `node` is `var` so that mutations through its computed setters
        // (which delegate to the shared store) compile. The struct copy is
        // local — the underlying store is shared.
        var node = node

        if !hasFDA, Self.isProtectedDirectory(node.url) {
            return
        }

        let enumerator = FileManager.default.enumerator(
            at: node.url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, error in
                if Self.isPermissionError(error) {
                    Task { await permissionCounter.increment() }
                }
                return true
            }
        )

        var subdirs: [URL] = []
        var directChildren: [FileNode] = []
        var smallFilesTotalSize: Int64 = 0
        var smallFilesCount = 0

        var localBytes: Int64 = 0
        var localItems: Int = 0
        var localFlushCounter = 0

        while let url = enumerator?.nextObject() as? URL {
            localItems += 1
            localFlushCounter += 1

            if localFlushCounter % 256 == 0 {
                try Task.checkCancellation()
                await Task.yield()
            }

            let resourceValues = try? url.resourceValues(forKeys: Self.resourceKeysSet)
            let isSymbolicLink = resourceValues?.isSymbolicLink ?? false
            let isDir = resourceValues?.isDirectory ?? false
            let isPackage = (resourceValues?.isPackage ?? false) || Self.isPackageURL(url)

            if isSymbolicLink { continue }
            if Self.shouldSkip(url) { continue }

            if isDir && !isPackage {
                if Self.skipDirectoryNames.contains(url.lastPathComponent) { continue }

                if Self.shouldShallowScan(url: url) {
                    let size = try await aggregateDeepSize(
                        subdirs: [url],
                        hasFDA: hasFDA,
                        permissionCounter: permissionCounter,
                        progress: progress
                    )
                    if size > 0 {
                        var child = FileNode(url: url, isDirectory: true, parent: node, store: node.store)
                        child.size = size
                        directChildren.append(child)
                    }
                } else {
                    subdirs.append(url)
                }
            } else {
                let fileSize = Int64(resourceValues?.fileAllocatedSize ?? resourceValues?.fileSize ?? 0)
                let linkCount = resourceValues?.linkCount ?? 1
                let modificationDate = resourceValues?.contentModificationDate

                var effectiveSize = fileSize
                if linkCount > 1 {
                    // Hard links to the same inode share `fileResourceIdentifier`
                    // (unique within a volume). Both identifiers come from the
                    // resourceValues already fetched — no extra stat syscall.
                    let isFirst = tracker.mark(
                        file: resourceValues?.fileResourceIdentifier,
                        volume: resourceValues?.volumeIdentifier
                    )
                    effectiveSize = isFirst ? fileSize : 0
                }

                localBytes += effectiveSize

                if effectiveSize < 100_000 {
                    smallFilesTotalSize += effectiveSize
                    smallFilesCount += 1
                } else {
                    var child = FileNode(url: url, isDirectory: false, parent: node, store: node.store)
                    child.size = effectiveSize
                    child.modificationDate = modificationDate
                    directChildren.append(child)
                }
            }

            if localFlushCounter >= 1024 {
                await progress.add(bytes: localBytes, items: localItems)
                localBytes = 0
                localItems = 0
                localFlushCounter = 0
            }
        }

        if localBytes > 0 || localItems > 0 {
            await progress.add(bytes: localBytes, items: localItems)
        }

        if smallFilesCount > 0 {
            let smallNodeURL = node.url.appendingPathComponent("[\(smallFilesCount) smaller files]")
            var smallNode = FileNode(url: smallNodeURL, isDirectory: false, parent: node, store: node.store)
            smallNode.size = smallFilesTotalSize
            directChildren.append(smallNode)
        }

        if depth >= maxDepth {
            let aggregatedSize = try await aggregateDeepSize(
                subdirs: subdirs,
                hasFDA: hasFDA,
                permissionCounter: permissionCounter,
                progress: progress
            )
            if aggregatedSize > 0 {
                let deepNodeURL = node.url.appendingPathComponent("[deeper items]")
                var deepNode = FileNode(url: deepNodeURL, isDirectory: true, parent: node, store: node.store)
                deepNode.size = aggregatedSize
                directChildren.append(deepNode)
            }

            directChildren.sort { $0.size > $1.size }
            node.children = directChildren
            node.size = directChildren.reduce(0) { $0 + $1.size }
            node.isScanned = true
            return
        }

        let scannedSubdirs = try await scanSubdirsInBatches(
            subdirs: subdirs,
            depth: depth,
            hasFDA: hasFDA,
            tracker: tracker,
            permissionCounter: permissionCounter,
            progress: progress,
            parent: node
        )

        try Task.checkCancellation()

        var allChildren = directChildren + scannedSubdirs
        allChildren.sort { $0.size > $1.size }

        if allChildren.count > maxChildrenPerNode {
            var kept = Array(allChildren.prefix(maxChildrenPerNode))
            let remaining = allChildren.suffix(allChildren.count - maxChildrenPerNode)
            let remainingSize = remaining.reduce(0) { $0 + $1.size }

            let othersURL = node.url.appendingPathComponent("[other folders]")
            var othersNode = FileNode(url: othersURL, isDirectory: true, parent: node, store: node.store)
            othersNode.size = remainingSize
            kept.append(othersNode)

            allChildren = kept
        }

        node.children = allChildren
        node.size = allChildren.reduce(0) { $0 + $1.size }
        node.isScanned = true
    }

    // MARK: - Aggregate deep size

    private static func aggregateDeepSize(
        subdirs: [URL],
        hasFDA: Bool,
        permissionCounter: PermissionErrorCounter,
        progress: ScanProgress
    ) async throws -> Int64 {
        var total: Int64 = 0
        for i in stride(from: 0, to: subdirs.count, by: maxConcurrentScans) {
            try Task.checkCancellation()
            let end = min(i + maxConcurrentScans, subdirs.count)
            let batch = Array(subdirs[i..<end])

            let batchTotal = try await withThrowingTaskGroup(of: Int64.self) { group in
                for dirURL in batch {
                    group.addTask {
                        try await Self.aggregateOneSubdir(
                            dirURL: dirURL,
                            hasFDA: hasFDA,
                            permissionCounter: permissionCounter,
                            progress: progress
                        )
                    }
                }

                var sum: Int64 = 0
                for try await result in group {
                    sum += result
                }
                return sum
            }
            total += batchTotal
        }
        return total
    }

    /// Sums the size of every file under `dirURL` without building nodes.
    private static func aggregateOneSubdir(
        dirURL: URL,
        hasFDA: Bool,
        permissionCounter: PermissionErrorCounter,
        progress: ScanProgress
    ) async throws -> Int64 {
        if !hasFDA, Self.isProtectedDirectory(dirURL) { return 0 }

        let enumerator = FileManager.default.enumerator(
            at: dirURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, error in
                if Self.isPermissionError(error) {
                    Task { await permissionCounter.increment() }
                }
                return true
            }
        )

        var total: Int64 = 0
        var localBytes: Int64 = 0
        var localItems: Int = 0
        var localFlushCounter = 0

        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Self.resourceKeysSet)
            let isSymbolicLink = values?.isSymbolicLink ?? false
            let isDir = values?.isDirectory ?? false
            let isPackage = (values?.isPackage ?? false) || Self.isPackageURL(url)
            if isSymbolicLink { continue }
            if isDir && !isPackage { continue }
            if Self.shouldSkip(url) { continue }

            let size = Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)
            total += size
            localBytes += size
            localItems += 1
            localFlushCounter += 1

            if localFlushCounter % 256 == 0 {
                try Task.checkCancellation()
                await Task.yield()
            }

            if localFlushCounter >= 1024 {
                await progress.add(bytes: localBytes, items: localItems)
                localBytes = 0
                localItems = 0
                localFlushCounter = 0
            }
        }

        if localBytes > 0 || localItems > 0 {
            await progress.add(bytes: localBytes, items: localItems)
        }
        return total
    }

    // MARK: - Parallel subdirectory scans

    private static func scanSubdirsInBatches(
        subdirs: [URL],
        depth: Int,
        hasFDA: Bool,
        tracker: InodeTracker,
        permissionCounter: PermissionErrorCounter,
        progress: ScanProgress,
        parent: FileNode
    ) async throws -> [FileNode] {
        var results: [FileNode] = []

        for i in stride(from: 0, to: subdirs.count, by: maxConcurrentScans) {
            let end = min(i + maxConcurrentScans, subdirs.count)
            let batch = Array(subdirs[i..<end])

            let batchResults = await withTaskGroup(of: FileNode?.self) { group in
                for dirURL in batch {
                    group.addTask {
                        let child = FileNode(url: dirURL, isDirectory: true, parent: parent, store: parent.store)
                        do {
                            try await scan(
                                node: child,
                                depth: depth + 1,
                                hasFDA: hasFDA,
                                tracker: tracker,
                                permissionCounter: permissionCounter,
                                progress: progress
                            )
                            return child
                        } catch {
                            return nil
                        }
                    }
                }

                var collected: [FileNode] = []
                for await case let child? in group {
                    collected.append(child)
                }
                return collected
            }

            results.append(contentsOf: batchResults)
            try Task.checkCancellation()
        }

        return results
    }

    // MARK: - Protected / skip paths

    private static let protectedHomePaths: [String] = [
        "Library/Calendars",
        "Library/Contacts",
        "Library/HomeKit",
        "Library/Mail",
        "Library/Messages",
        "Library/Photos",
        "Library/Reminders",
        "Library/Safari",
        "Library/Application Support/AddressBook",
        "Music",
        "Pictures",
        "Movies"
    ]

    private static var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func isProtectedDirectory(_ url: URL) -> Bool {
        let path = url.path
        guard path.hasPrefix(homePath) else { return false }
        let relative = String(path.dropFirst(homePath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        if relative.hasPrefix("Library/") { return true }
        return protectedHomePaths.contains(relative) || protectedHomePaths.contains { relative.hasPrefix($0 + "/") }
    }

    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "pkg",
        "xcodeproj", "xcworkspace", "playground", "photoslibrary",
        "sparsebundle", "ipynb", "rtfd"
    ]

    private static func isPackageURL(_ url: URL) -> Bool {
        packageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(EPERM) || nsError.code == Int(EACCES)) {
            return true
        }
        return false
    }

    static var hasFullDiskAccess: Bool {
        let testPath = "/Library/Preferences/com.apple.TimeMachine.plist"
        return FileManager.default.isReadableFile(atPath: testPath)
    }
}

actor PermissionErrorCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var hasErrors: Bool {
        count > 0
    }
}
