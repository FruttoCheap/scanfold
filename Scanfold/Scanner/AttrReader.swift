import Foundation
import Darwin

/// One directory entry as returned by getattrlistbulk(2).
struct DirEntry {
    let name: String
    let objType: UInt32
    let devID: UInt32
    let fileID: UInt64
    let linkCount: UInt32
    let allocSize: UInt64
    let privateSize: UInt64
    let flags: UInt32
    let mountStatus: UInt32

    var isDir: Bool { objType == Attr.vDir }
    var isLink: Bool { objType == Attr.vLnk }
    var isFirmlink: Bool { flags & Attr.firmlink != 0 }
    var isMountPoint: Bool { mountStatus & Attr.mountPoint != 0 }
}

/// Reads a directory with getattrlistbulk, returning every entry with metadata.
enum AttrReader {
    static func read(_ path: String) -> [DirEntry] {
        let dirfd = open(path, O_RDONLY | O_DIRECTORY)
        guard dirfd >= 0 else { return [] }
        defer { close(dirfd) }

        var al = attrlist()
        al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        al.commonattr = Attr.returnedAttrs | Attr.name | Attr.devID |
                        Attr.objType | Attr.fileID | Attr.flags
        al.fileattr = Attr.fileLinkCount | Attr.fileAllocSize
        al.dirattr = Attr.dirMountStatus
        al.forkattr = Attr.cmnextPrivateSize

        var entries: [DirEntry] = []
        let bufSize = 256 * 1024
        var buf = [UInt8](repeating: 0, count: bufSize)

        while true {
            let n = buf.withUnsafeMutableBytes { raw -> Int32 in
                withUnsafeMutablePointer(to: &al) { alPtr in
                    getattrlistbulk(Int32(dirfd), alPtr, raw.baseAddress, bufSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
                }
            }
            if n <= 0 { break }

            // getattrlistbulk returns the number of *entries*, not bytes.
            var pos = 0
            for _ in 0..<Int(n) {
                let len = Int(buf[pos]) | (Int(buf[pos + 1]) << 8) |
                          (Int(buf[pos + 2]) << 16) | (Int(buf[pos + 3]) << 24)
                if len <= 0 || pos + len > buf.count { break }
                if let e = parse(&buf, pos: pos) { entries.append(e) }
                pos += len
            }
        }
        return entries
    }

    /// Walks one entry. The kernel lays attributes out in the order they are
    /// declared in <sys/attr.h>; only requested attributes are present.
    private static func parse(_ buf: inout [UInt8], pos: Int) -> DirEntry? {
        let base = buf.withUnsafeBytes { $0.baseAddress! }
        // Layout: [u32 length][attribute_set_t][attributes...]
        let ret = base.advanced(by: pos + 4).assumingMemoryBound(to: attribute_set_t.self)
        let common = ret.pointee.commonattr
        let file = ret.pointee.fileattr
        let dir = ret.pointee.dirattr
        let fork = ret.pointee.forkattr

        var q = base.advanced(by: pos + 4 + MemoryLayout<attribute_set_t>.size)

        func u32() -> UInt32 { let v = q.assumingMemoryBound(to: UInt32.self).pointee; q += 4; return v }
        func u64() -> UInt64 { let v = q.assumingMemoryBound(to: UInt64.self).pointee; q += 8; return v }
        func skip(_ n: Int) { q += n }

        var name = ""
        if common & Attr.name != 0 {
            let ref = q.assumingMemoryBound(to: attrreference.self).pointee
            let namePtr = q.advanced(by: Int(ref.attr_dataoffset))
            name = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
            skip(MemoryLayout<attrreference>.size)
        }
        let devID = common & Attr.devID != 0 ? u32() : 0
        if common & Attr.fsid != 0 { skip(8) }
        let objType = common & Attr.objType != 0 ? u32() : 0
        if common & Attr.objTag != 0 { skip(4) }
        if common & Attr.objID != 0 { skip(16) }
        if common & Attr.parObjID != 0 { skip(16) }
        if common & Attr.script != 0 { skip(4) }
        if common & Attr.crTime != 0 { skip(16) }
        if common & Attr.modTime != 0 { skip(16) }
        if common & Attr.chgTime != 0 { skip(16) }
        if common & Attr.accTime != 0 { skip(16) }
        if common & Attr.bkupTime != 0 { skip(16) }
        if common & Attr.fndrInfo != 0 { skip(32) }
        if common & Attr.ownerID != 0 { skip(4) }
        if common & Attr.grpID != 0 { skip(4) }
        if common & Attr.accessMask != 0 { skip(4) }
        let flags = common & Attr.flags != 0 ? u32() : 0
        if common & Attr.genCount != 0 { skip(4) }
        if common & Attr.documentID != 0 { skip(4) }
        if common & Attr.userAccess != 0 { skip(4) }
        if common & Attr.extendedSecurity != 0 { skip(8) }
        if common & Attr.uuid != 0 { skip(16) }
        if common & Attr.grpUUID != 0 { skip(16) }
        let fileID = common & Attr.fileID != 0 ? u64() : 0
        if common & Attr.parentID != 0 { skip(8) }
        if common & Attr.fullPath != 0 { skip(8) }
        if common & Attr.addedTime != 0 { skip(16) }
        if common & Attr.error != 0 { skip(4) }
        if common & Attr.dataProtectFlags != 0 { skip(4) }

        let linkCount = file & Attr.fileLinkCount != 0 ? u32() : 1
        if file & Attr.fileTotalSize != 0 { skip(8) }
        let allocSize = file & Attr.fileAllocSize != 0 ? u64() : 0
        if file & Attr.fileIOBlockSize != 0 { skip(4) }
        if file & Attr.fileDevType != 0 { skip(4) }
        if file & Attr.fileFileType != 0 { skip(4) }
        if file & Attr.fileForkCount != 0 { skip(4) }
        if file & Attr.fileForkList != 0 { skip(8) }
        if file & Attr.fileDataLength != 0 { skip(8) }
        if file & Attr.fileDataAllocSize != 0 { skip(8) }
        if file & Attr.fileRsrcLength != 0 { skip(8) }
        if file & Attr.fileRsrcAllocSize != 0 { skip(8) }

        if dir & Attr.dirLinkCount != 0 { skip(4) }
        if dir & Attr.dirEntryCount != 0 { skip(4) }
        let mountStatus = dir & Attr.dirMountStatus != 0 ? u32() : 0
        if dir & Attr.dirAllocSize != 0 { skip(8) }
        if dir & Attr.dirIOBlockSize != 0 { skip(4) }
        if dir & Attr.dirDataLength != 0 { skip(8) }

        let privateSize = fork & Attr.cmnextPrivateSize != 0 ? u64() : 0

        return DirEntry(name: name, objType: objType, devID: devID, fileID: fileID,
                        linkCount: linkCount, allocSize: allocSize, privateSize: privateSize,
                        flags: flags, mountStatus: mountStatus)
    }
}
