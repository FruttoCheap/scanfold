import Foundation
import Darwin

/// Walks the file tree with high-performance multi-threaded traversal and fills a `FileTree`.
///
/// Performance and correctness optimizations:
/// - Concurrent worker pool automatically scaled to available CPU cores.
/// - Hard links (linkcount > 1) are counted once, keyed by (devid, fileid).
/// - Firmlinks (SF_FIRMLINK) are skipped to avoid double counting.
/// - Mount points other than the root volume are skipped.
/// - Small files (< 1MB) are aggregated in-place during directory enumeration,
///   eliminating millions of heap allocations, string conversions, and O(N^2) list detaches.
/// - Per-worker reusable buffers to eliminate heap allocator churn and page zeroing.
/// - Dynamic file descriptor limit expansion via `setrlimit`.
final class Scanner: @unchecked Sendable {
    struct Progress: Sendable {
        let scanned: Int
        let totalSize: UInt64
        let currentPath: String
        let errors: Int
    }

    struct Result: Sendable {
        let tree: FileTree
        let errors: Int
        let files: Int
    }

    let rootPath: String
    let smallFileThreshold: UInt64 = 1_000_000

    private let tree = FileTree()
    private var seenLock = os_unfair_lock_s()
    private var seen: Set<UInt64> = []

    private var statsLock = os_unfair_lock_s()
    private var scanned: Int = 0
    private var totalSize: UInt64 = 0
    private var errors: Int = 0
    private var lastEmit = ContinuousClock.now

    private var continuationLock = os_unfair_lock_s()
    private var continuation: AsyncStream<Progress>.Continuation?

    private var cancelLock = os_unfair_lock_s()
    private var _cancelled = false

    var isCancelled: Bool {
        os_unfair_lock_lock(&cancelLock)
        let c = _cancelled
        os_unfair_lock_unlock(&cancelLock)
        return c
    }

    init(rootPath: String = "/System/Volumes/Data") {
        self.rootPath = rootPath
    }

    func progressStream() -> AsyncStream<Progress> {
        AsyncStream { continuation in
            os_unfair_lock_lock(&self.continuationLock)
            self.continuation = continuation
            os_unfair_lock_unlock(&self.continuationLock)
        }
    }

    func cancel() {
        os_unfair_lock_lock(&cancelLock)
        _cancelled = true
        os_unfair_lock_unlock(&cancelLock)
    }

    func scan() async -> Result {
        // Raise file descriptor limit so concurrent directory reading never hits EMFILE
        var rl = rlimit()
        if getrlimit(RLIMIT_NOFILE, &rl) == 0 {
            rl.rlim_cur = min(rl.rlim_max, 10240)
            setrlimit(RLIMIT_NOFILE, &rl)
        }

        var st = stat()
        var rootDev: UInt32 = 0
        if stat(rootPath, &st) == 0 {
            rootDev = UInt32(truncatingIfNeeded: st.st_dev)
        }

        tree.setRoot(name: (rootPath as NSString).lastPathComponent, path: rootPath)

        await withCheckedContinuation { cc in
            DispatchQueue.global(qos: .userInteractive).async {
                self.runScan(rootDev: rootDev)
                cc.resume()
            }
        }

        tree.recomputeAllSizes()
        finishProgress()
        return Result(tree: tree, errors: errors, files: scanned)
    }

    /// Sends the final progress and closes the stream. Kept sync: os_unfair_lock can't be used from async code.
    private func finishProgress() {
        os_unfair_lock_lock(&continuationLock)
        let cont = continuation
        os_unfair_lock_unlock(&continuationLock)

        cont?.yield(Progress(scanned: scanned, totalSize: totalSize, currentPath: rootPath, errors: errors))
        cont?.finish()
    }

    private func runScan(rootDev: UInt32) {
        var stack: [(path: String, parentIndex: Int)] = [(rootPath, 0)]
        var activeWorkers = 0
        let condition = NSCondition()
        var done = false

        let workerCount = min(16, max(4, ProcessInfo.processInfo.activeProcessorCount))
        let group = DispatchGroup()

        for _ in 0..<workerCount {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                guard let self else { group.leave(); return }
                defer { group.leave() }

                // Per-worker 64 KB buffer reused across all directory reads
                let bufSize = 64 * 1024
                let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
                defer { buf.deallocate() }

                var al = attrlist()
                al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
                al.commonattr = Attr.returnedAttrs | Attr.name | Attr.devID |
                                Attr.objType | Attr.fileID | Attr.flags
                al.fileattr = Attr.fileLinkCount | Attr.fileAllocSize
                al.dirattr = Attr.dirMountStatus

                while true {
                    condition.lock()
                    while stack.isEmpty && !done && activeWorkers > 0 && !self.isCancelled {
                        condition.wait()
                    }
                    if self.isCancelled || (stack.isEmpty && activeWorkers == 0) {
                        done = true
                        condition.broadcast()
                        condition.unlock()
                        break
                    }
                    let item = stack.removeLast()
                    activeWorkers += 1
                    condition.unlock()

                    var localSubdirs: [(path: String, parentIndex: Int)] = []
                    var localFilesCount = 0
                    var localAlloc: UInt64 = 0

                    let dirfd = open(item.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                    if dirfd < 0 {
                        os_unfair_lock_lock(&self.statsLock)
                        self.errors += 1
                        os_unfair_lock_unlock(&self.statsLock)
                    } else {
                        var smallCount = 0
                        var smallAlloc: UInt64 = 0

                        while !self.isCancelled {
                            let n = getattrlistbulk(dirfd, &al, buf, bufSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
                            if n <= 0 { break }

                            var q = buf
                            for _ in 0..<Int(n) {
                                let entryLength = Int(q.assumingMemoryBound(to: UInt32.self).pointee)
                                if entryLength <= 0 { break }
                                let entryBase = q
                                let ret = q.advanced(by: 4).assumingMemoryBound(to: attribute_set_t.self).pointee

                                var p = q.advanced(by: 4 + MemoryLayout<attribute_set_t>.size)

                                var namePtr: UnsafePointer<CChar>?
                                if ret.commonattr & Attr.name != 0 {
                                    let ref = p.assumingMemoryBound(to: attrreference.self).pointee
                                    namePtr = UnsafePointer(p.advanced(by: Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                                    p += MemoryLayout<attrreference>.size
                                }

                                let devID = ret.commonattr & Attr.devID != 0 ? p.assumingMemoryBound(to: UInt32.self).pointee : 0
                                if ret.commonattr & Attr.devID != 0 { p += 4 }

                                let objType = ret.commonattr & Attr.objType != 0 ? p.assumingMemoryBound(to: UInt32.self).pointee : 0
                                if ret.commonattr & Attr.objType != 0 { p += 4 }

                                let flags = ret.commonattr & Attr.flags != 0 ? p.assumingMemoryBound(to: UInt32.self).pointee : 0
                                if ret.commonattr & Attr.flags != 0 { p += 4 }

                                let fileID = ret.commonattr & Attr.fileID != 0 ? p.assumingMemoryBound(to: UInt64.self).pointee : 0
                                if ret.commonattr & Attr.fileID != 0 { p += 8 }

                                let linkCount = ret.fileattr & Attr.fileLinkCount != 0 ? p.assumingMemoryBound(to: UInt32.self).pointee : 1
                                if ret.fileattr & Attr.fileLinkCount != 0 { p += 4 }

                                let allocSize = ret.fileattr & Attr.fileAllocSize != 0 ? p.assumingMemoryBound(to: UInt64.self).pointee : 0
                                if ret.fileattr & Attr.fileAllocSize != 0 { p += 8 }

                                let mountStatus = ret.dirattr & Attr.dirMountStatus != 0 ? p.assumingMemoryBound(to: UInt32.self).pointee : 0

                                q = entryBase.advanced(by: entryLength)

                                guard let np = namePtr else { continue }
                                let firstChar = np.pointee
                                if firstChar == 46 { // '.'
                                    if np.advanced(by: 1).pointee == 0 { continue } // "."
                                    if np.advanced(by: 1).pointee == 46 && np.advanced(by: 2).pointee == 0 { continue } // ".."
                                }

                                if flags & Attr.firmlink != 0 { continue }
                                if devID != rootDev { continue }
                                if objType == Attr.vLnk { continue }

                                if objType == Attr.vDir {
                                    if mountStatus & Attr.mountPoint != 0 { continue }
                                    let name = String(cString: np)
                                    let subpath = item.path == "/" ? "/\(name)" : "\(item.path)/\(name)"
                                    let idx = self.tree.add(name: name, path: subpath, allocSize: 0, isDir: true, parent: item.parentIndex)
                                    localSubdirs.append((subpath, idx))
                                } else {
                                    if linkCount > 1 {
                                        let key = (UInt64(devID) << 48) | fileID
                                        os_unfair_lock_lock(&self.seenLock)
                                        let inserted = self.seen.insert(key).inserted
                                        os_unfair_lock_unlock(&self.seenLock)
                                        if !inserted { continue }
                                    }

                                    localFilesCount += 1
                                    localAlloc += allocSize

                                    if allocSize < self.smallFileThreshold {
                                        smallCount += 1
                                        smallAlloc += allocSize
                                    } else {
                                        let name = String(cString: np)
                                        let subpath = item.path == "/" ? "/\(name)" : "\(item.path)/\(name)"
                                        self.tree.add(name: name, path: subpath, allocSize: allocSize, isDir: false, parent: item.parentIndex)
                                    }
                                }
                            }
                        }
                        close(dirfd)

                        if smallCount > 0 {
                            self.tree.add(name: "Small files (\(smallCount))", path: "", allocSize: smallAlloc, isDir: false, isAggregate: true, parent: item.parentIndex)
                        }
                    }

                    os_unfair_lock_lock(&self.statsLock)
                    self.scanned += localFilesCount
                    self.totalSize += localAlloc
                    let now = ContinuousClock.now
                    var shouldEmit = false
                    if now - self.lastEmit >= .milliseconds(100) {
                        self.lastEmit = now
                        shouldEmit = true
                    }
                    let currentScanned = self.scanned
                    let currentTotal = self.totalSize
                    let currentErrors = self.errors
                    os_unfair_lock_unlock(&self.statsLock)

                    if shouldEmit {
                        os_unfair_lock_lock(&self.continuationLock)
                        let cont = self.continuation
                        os_unfair_lock_unlock(&self.continuationLock)
                        cont?.yield(Progress(scanned: currentScanned, totalSize: currentTotal, currentPath: item.path, errors: currentErrors))
                    }

                    condition.lock()
                    activeWorkers -= 1
                    if !localSubdirs.isEmpty && !self.isCancelled {
                        stack.append(contentsOf: localSubdirs)
                        condition.broadcast()
                    } else if stack.isEmpty && activeWorkers == 0 {
                        done = true
                        condition.broadcast()
                    }
                    condition.unlock()
                }
            }
        }

        group.wait()
    }
}
