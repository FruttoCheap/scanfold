import Foundation

struct VolumeInfo {
    let totalCapacity: UInt64
    let availableCapacity: UInt64
    let availableCapacityForImportantUsage: UInt64

    /// Space that can be reclaimed by the system at any time.
    var purgeableSpace: UInt64 {
        availableCapacityForImportantUsage > availableCapacity
            ? availableCapacityForImportantUsage - availableCapacity
            : 0
    }

    var usedSpace: UInt64 {
        totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
    }

    static func forRootVolume() -> VolumeInfo? {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return nil }

        return VolumeInfo(
            totalCapacity: UInt64(v.volumeTotalCapacity ?? 0),
            availableCapacity: UInt64(v.volumeAvailableCapacity ?? 0),
            availableCapacityForImportantUsage: UInt64(v.volumeAvailableCapacityForImportantUsage ?? 0)
        )
    }

    /// Local Time Machine snapshots. Deleting them needs admin, so the app
    /// only lists them.
    static func localSnapshots() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        task.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty } ?? []
        } catch {
            return []
        }
    }

    var formattedTotal: String { Self.fmt(totalCapacity) }
    var formattedAvailable: String { Self.fmt(availableCapacity) }
    var formattedPurgeable: String { Self.fmt(purgeableSpace) }
    var formattedUsed: String { Self.fmt(usedSpace) }

    static func fmt(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
