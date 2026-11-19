import Darwin

/// Swift imports the `ATTR_*` macros as `Int32`, but the `attrlist` fields are
/// `UInt32`. These are the same values, typed correctly.
enum Attr {
    static let returnedAttrs: UInt32 = UInt32(ATTR_CMN_RETURNED_ATTRS)
    static let name: UInt32 = UInt32(ATTR_CMN_NAME)
    static let devID: UInt32 = UInt32(ATTR_CMN_DEVID)
    static let objType: UInt32 = UInt32(ATTR_CMN_OBJTYPE)
    static let flags: UInt32 = UInt32(ATTR_CMN_FLAGS)
    static let fileID: UInt32 = UInt32(ATTR_CMN_FILEID)

    static let fileLinkCount: UInt32 = UInt32(ATTR_FILE_LINKCOUNT)
    static let fileAllocSize: UInt32 = UInt32(ATTR_FILE_ALLOCSIZE)

    static let dirMountStatus: UInt32 = UInt32(ATTR_DIR_MOUNTSTATUS)

    static let vDir: UInt32 = VDIR.rawValue
    static let vLnk: UInt32 = VLNK.rawValue

    static let firmlink: UInt32 = UInt32(SF_FIRMLINK)
    static let mountPoint: UInt32 = UInt32(DIR_MNTSTATUS_MNTPOINT)
}
