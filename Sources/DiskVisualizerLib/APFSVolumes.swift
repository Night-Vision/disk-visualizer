import Foundation

/// Per-volume physical usage for the APFS container behind a given path.
///
/// APFS pools blocks across every volume in a container, so `statfs` — and
/// therefore `URLResourceValues.volumeAvailableCapacity` — reports *container*
/// usage for each one alike: `/`, `/System/Volumes/VM` and `/System/Volumes/Preboot`
/// all answer with the same number. `diskutil` is the only unprivileged source
/// of a real per-volume figure.
enum APFSVolumes {
    struct Sibling: Sendable {
        /// Volume name, which is also its mount point under `/System/Volumes`.
        let name: String
        let bytes: Int64
    }

    /// Every volume in `url`'s container except System and Data — on a stock
    /// Mac that is Preboot, Recovery, VM and Update. A scan of `/` cannot reach
    /// them: Preboot/VM/Update are separate mounts under `/System/Volumes`, and
    /// Recovery is not mounted at all.
    ///
    /// Returns `[]` on any failure. A missing or uncooperative `diskutil` must
    /// degrade to the old behaviour, never fail a scan.
    ///
    /// ponytail: sizes only, contents are not walked. Walking Preboot reports
    /// 28 GB against 9.1 GB physical because its files are APFS clones sharing
    /// blocks with the System volume (`du` gets this equally wrong). Walk them
    /// if browsing inside ever matters, but keep these numbers for the totals.
    static func siblings(of url: URL) -> [Sibling] {
        guard let info = plist(["info", "-plist", url.path]),
              let container = info["APFSContainerReference"] as? String,
              let list = plist(["apfs", "list", "-plist"]),
              let containers = list["Containers"] as? [[String: Any]] else {
            return []
        }

        guard let match = containers.first(where: { $0["ContainerReference"] as? String == container }),
              let volumes = match["Volumes"] as? [[String: Any]] else {
            return []
        }

        return volumes.compactMap { volume in
            let roles = Set(volume["Roles"] as? [String] ?? [])
            // System and Data are already counted by the file walk: `/` is the
            // System volume, and Data is reached through the root firmlinks.
            guard roles.isDisjoint(with: ["System", "Data"]) else { return nil }
            guard let name = volume["Name"] as? String,
                  let bytes = volume["CapacityInUse"] as? Int64, bytes > 0 else { return nil }
            return Sibling(name: name, bytes: bytes)
        }
    }

    private static func plist(_ arguments: [String]) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        // Drain before waiting: `apfs list -plist` is only a few KB today, but
        // waiting first on a full pipe buffer would deadlock.
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }

        return try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]
    }
}
