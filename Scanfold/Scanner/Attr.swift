import Darwin

/// Swift imports the `ATTR_*` macros as `Int32`, but the `attrlist` fields are
/// `UInt32`. These are the same values, typed correctly.
enum Attr {
    static let returnedAttrs: UInt32 = UInt32(ATTR_CMN_RETURNED_ATTRS)
    static let name: UInt32 = UInt32(ATTR_CMN_NAME)
    static let devID: UInt32 = UInt32(ATTR_CMN_DEVID)
    static let fsid: UInt32 = UInt32(ATTR_CMN_FSID)
    static let objType: UInt32 = UInt32(ATTR_CMN_OBJTYPE)
    static let objTag: UInt32 = UInt32(ATTR_CMN_OBJTAG)
    static let objID: UInt32 = UInt32(ATTR_CMN_OBJID)
    static let parObjID: UInt32 = UInt32(ATTR_CMN_PAROBJID)
    static let script: UInt32 = UInt32(ATTR_CMN_SCRIPT)
    static let crTime: UInt32 = UInt32(ATTR_CMN_CRTIME)
    static let modTime: UInt32 = UInt32(ATTR_CMN_MODTIME)
    static let chgTime: UInt32 = UInt32(ATTR_CMN_CHGTIME)
    static let accTime: UInt32 = UInt32(ATTR_CMN_ACCTIME)
    static let bkupTime: UInt32 = UInt32(ATTR_CMN_BKUPTIME)
    static let fndrInfo: UInt32 = UInt32(ATTR_CMN_FNDRINFO)
    static let ownerID: UInt32 = UInt32(ATTR_CMN_OWNERID)
    static let grpID: UInt32 = UInt32(ATTR_CMN_GRPID)
    static let accessMask: UInt32 = UInt32(ATTR_CMN_ACCESSMASK)
    static let flags: UInt32 = UInt32(ATTR_CMN_FLAGS)
    static let genCount: UInt32 = UInt32(ATTR_CMN_GEN_COUNT)
    static let documentID: UInt32 = UInt32(ATTR_CMN_DOCUMENT_ID)
    static let userAccess: UInt32 = UInt32(ATTR_CMN_USERACCESS)
    static let extendedSecurity: UInt32 = UInt32(ATTR_CMN_EXTENDED_SECURITY)
    static let uuid: UInt32 = UInt32(ATTR_CMN_UUID)
    static let grpUUID: UInt32 = UInt32(ATTR_CMN_GRPUUID)
    static let fileID: UInt32 = UInt32(ATTR_CMN_FILEID)
    static let parentID: UInt32 = UInt32(ATTR_CMN_PARENTID)
    static let fullPath: UInt32 = UInt32(ATTR_CMN_FULLPATH)
    static let addedTime: UInt32 = UInt32(ATTR_CMN_ADDEDTIME)
    static let error: UInt32 = UInt32(ATTR_CMN_ERROR)
    static let dataProtectFlags: UInt32 = UInt32(ATTR_CMN_DATA_PROTECT_FLAGS)

    static let fileLinkCount: UInt32 = UInt32(ATTR_FILE_LINKCOUNT)
    static let fileTotalSize: UInt32 = UInt32(ATTR_FILE_TOTALSIZE)
    static let fileAllocSize: UInt32 = UInt32(ATTR_FILE_ALLOCSIZE)
    static let fileIOBlockSize: UInt32 = UInt32(ATTR_FILE_IOBLOCKSIZE)
    static let fileDevType: UInt32 = UInt32(ATTR_FILE_DEVTYPE)
    static let fileFileType: UInt32 = UInt32(ATTR_FILE_FILETYPE)
    static let fileForkCount: UInt32 = UInt32(ATTR_FILE_FORKCOUNT)
    static let fileForkList: UInt32 = UInt32(ATTR_FILE_FORKLIST)
    static let fileDataLength: UInt32 = UInt32(ATTR_FILE_DATALENGTH)
    static let fileDataAllocSize: UInt32 = UInt32(ATTR_FILE_DATAALLOCSIZE)
    static let fileRsrcLength: UInt32 = UInt32(ATTR_FILE_RSRCLENGTH)
    static let fileRsrcAllocSize: UInt32 = UInt32(ATTR_FILE_RSRCALLOCSIZE)

    static let dirLinkCount: UInt32 = UInt32(ATTR_DIR_LINKCOUNT)
    static let dirEntryCount: UInt32 = UInt32(ATTR_DIR_ENTRYCOUNT)
    static let dirMountStatus: UInt32 = UInt32(ATTR_DIR_MOUNTSTATUS)
    static let dirAllocSize: UInt32 = UInt32(ATTR_DIR_ALLOCSIZE)
    static let dirIOBlockSize: UInt32 = UInt32(ATTR_DIR_IOBLOCKSIZE)
    static let dirDataLength: UInt32 = UInt32(ATTR_DIR_DATALENGTH)

    static let cmnextPrivateSize: UInt32 = UInt32(ATTR_CMNEXT_PRIVATESIZE)

    static let vDir: UInt32 = VDIR.rawValue
    static let vReg: UInt32 = VREG.rawValue
    static let vLnk: UInt32 = VLNK.rawValue

    static let firmlink: UInt32 = UInt32(SF_FIRMLINK)
    static let mountPoint: UInt32 = UInt32(DIR_MNTSTATUS_MNTPOINT)
}
