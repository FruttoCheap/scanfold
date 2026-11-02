import Foundation

/// Handles persistent caching of the last scan result.
enum ScanStorage {
    private static let magic: UInt32 = 0x53434E46 // "SCNF"
    private static let currentVersion: UInt32 = 1
    private static let queue = DispatchQueue(label: "com.giuliodesana.scanfold.storage", qos: .utility)

    struct SavedScan {
        let tree: FileTree
        let errorCount: Int
        let date: Date
    }

    private static var storageURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("Scanfold", isDirectory: true).appendingPathComponent("last_scan.bin")
    }

    /// Loads the last saved scan synchronously. Returns `nil` if no scan is cached or if loading fails.
    static func load() -> SavedScan? {
        guard let url = storageURL, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            guard let result = deserialize(data: data) else {
                // If the cache file is invalid/corrupted, remove it
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return result
        } catch {
            return nil
        }
    }

    /// Asynchronously saves the tree snapshot to disk.
    static func save(tree: FileTree, errorCount: Int, date: Date = Date()) {
        guard let url = storageURL else { return }
        // Snapshot the node array to prevent race conditions during background writing
        let nodesSnapshot = tree.nodes

        queue.async {
            let data = serialize(nodes: nodesSnapshot, errorCount: errorCount, date: date)
            let folderURL = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: folderURL.path) {
                try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Ensures all pending write operations complete before terminating.
    static func waitForPendingWrites() {
        queue.sync {}
    }

    // MARK: - Serialization

    static func serialize(nodes: [FileTree.Node], errorCount: Int, date: Date) -> Data {
        var estimatedSize = 32
        for n in nodes {
            estimatedSize += 71 + n.name.utf8.count + n.path.utf8.count
        }

        var data = Data(capacity: estimatedSize)
        var m = magic
        var v = currentVersion
        var ts = date.timeIntervalSince1970
        var errs = Int64(errorCount)
        var count = Int64(nodes.count)

        withUnsafeBytes(of: &m) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &ts) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &errs) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }

        for n in nodes {
            var alloc = n.allocSize
            var priv = n.privateSize
            var p = Int64(n.parent)
            var fc = Int64(n.firstChild)
            var lc = Int64(n.lastChild)
            var ns = Int64(n.nextSibling)
            var cc = Int64(n.childCount)
            var fcCount = Int64(n.fileCount)
            let flags: UInt8 = (n.isDir ? 1 : 0) | (n.isAggregate ? 2 : 0)

            withUnsafeBytes(of: &alloc) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &priv) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &p) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &fc) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &lc) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &ns) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &cc) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &fcCount) { data.append(contentsOf: $0) }
            data.append(flags)

            let nameBytes = n.name.utf8
            var nameLen = UInt16(min(nameBytes.count, Int(UInt16.max)))
            withUnsafeBytes(of: &nameLen) { data.append(contentsOf: $0) }
            data.append(contentsOf: nameBytes.prefix(Int(nameLen)))

            let pathBytes = n.path.utf8
            var pathLen = UInt32(pathBytes.count)
            withUnsafeBytes(of: &pathLen) { data.append(contentsOf: $0) }
            data.append(contentsOf: pathBytes)
        }
        return data
    }

    // MARK: - Deserialization

    static func deserialize(data: Data) -> SavedScan? {
        guard data.count >= 32 else { return nil }
        var decodedNodes = [FileTree.Node]()
        var decodedErrors = 0
        var decodedDate = Date()

        let success: Bool = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var offset = 0

            func readUnaligned<T>(_ type: T.Type) -> T? {
                guard offset + MemoryLayout<T>.size <= raw.count else { return nil }
                let val = raw.loadUnaligned(fromByteOffset: offset, as: T.self)
                offset += MemoryLayout<T>.size
                return val
            }

            guard let m = readUnaligned(UInt32.self), m == magic else { return false }
            guard let v = readUnaligned(UInt32.self), v == currentVersion else { return false }
            guard let ts = readUnaligned(Double.self) else { return false }
            decodedDate = Date(timeIntervalSince1970: ts)
            guard let errs = readUnaligned(Int64.self) else { return false }
            decodedErrors = Int(errs)
            guard let count64 = readUnaligned(Int64.self), count64 >= 1, count64 <= 50_000_000 else { return false }
            let count = Int(count64)

            decodedNodes.reserveCapacity(count)

            for _ in 0..<count {
                guard let alloc = readUnaligned(UInt64.self),
                      let priv = readUnaligned(UInt64.self),
                      let p = readUnaligned(Int64.self),
                      let fc = readUnaligned(Int64.self),
                      let lc = readUnaligned(Int64.self),
                      let ns = readUnaligned(Int64.self),
                      let cc = readUnaligned(Int64.self),
                      let fcCount = readUnaligned(Int64.self),
                      let flags = readUnaligned(UInt8.self),
                      let nameLen16 = readUnaligned(UInt16.self) else {
                    return false
                }

                let nameLen = Int(nameLen16)
                guard offset + nameLen <= raw.count else { return false }
                let namePtr = base.advanced(by: offset)
                offset += nameLen
                let name = String(decoding: UnsafeRawBufferPointer(start: namePtr, count: nameLen), as: UTF8.self)

                guard let pathLen32 = readUnaligned(UInt32.self) else { return false }
                let pathLen = Int(pathLen32)
                guard offset + pathLen <= raw.count else { return false }
                let pathPtr = base.advanced(by: offset)
                offset += pathLen
                let path = String(decoding: UnsafeRawBufferPointer(start: pathPtr, count: pathLen), as: UTF8.self)

                decodedNodes.append(FileTree.Node(
                    name: name,
                    path: path,
                    allocSize: alloc,
                    privateSize: priv,
                    parent: Int(p),
                    firstChild: Int(fc),
                    lastChild: Int(lc),
                    nextSibling: Int(ns),
                    childCount: Int(cc),
                    fileCount: Int(fcCount),
                    isDir: (flags & 1) != 0,
                    isAggregate: (flags & 2) != 0
                ))
            }
            return true
        }

        guard success, !decodedNodes.isEmpty else { return nil }
        return SavedScan(tree: FileTree(nodes: decodedNodes), errorCount: decodedErrors, date: decodedDate)
    }
}
