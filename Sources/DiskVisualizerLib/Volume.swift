import Foundation

struct Volume: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64

    var usedCapacity: Int64 { totalCapacity - availableCapacity }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }
}

/// Enumerate all mounted volumes on this Mac.
func listVolumes() -> [Volume] {
    let keys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
    ]

    guard let urls = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: keys,
        options: [.skipHiddenVolumes]
    ) else {
        return []
    }

    return urls.compactMap { url in
        let values = try? url.resourceValues(forKeys: Set(keys))
        let name = values?.volumeName ?? url.lastPathComponent
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = Int64(values?.volumeAvailableCapacity ?? 0)
        return Volume(url: url, name: name.isEmpty ? url.path : name, totalCapacity: total, availableCapacity: available)
    }
}
