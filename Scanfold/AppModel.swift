import SwiftUI
import AppKit
import QuickLook

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var tree: FileTree?
    @Published private(set) var current: Int = 0
    @Published private(set) var isScanning = false
    @Published private(set) var revision = 0
    @Published private(set) var progress: Scanner.Progress?
    @Published private(set) var errorCount = 0
    @Published private(set) var volumeInfo: VolumeInfo?
    @Published var hoveredNode: Int?
    @Published var collected: [Int] = []
    @Published var showDeleteConfirmation = false
    @Published var quickLookURL: URL?
    let hasDiskAccess: Bool

    private var scanner: Scanner?
    private var scanTask: Task<Void, Never>?

    init() {
        // TCC.db exists on every Mac and opens only with Full Disk Access. macOS applies a new grant on relaunch.
        hasDiskAccess = FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") != nil
        volumeInfo = VolumeInfo.forRootVolume()
        if let cached = ScanStorage.load() {
            self.tree = cached.tree
            self.current = cached.tree.root
            self.errorCount = cached.errorCount
            self.revision = 1
        }
    }

    func openDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        progress = nil
        errorCount = 0
        collected = []

        let scanner = Scanner()
        self.scanner = scanner
        let stream = scanner.progressStream()
        self.revision = 0

        scanTask = Task {
            for await update in stream {
                if Task.isCancelled { break }
                self.progress = update
                self.errorCount = update.errors
            }
        }

        Task {
            let result = await scanner.scan()
            guard !scanner.isCancelled else { return }   // Stop keeps the previous result
            self.tree = result.tree
            self.current = result.tree.root
            self.errorCount = result.errors
            self.isScanning = false
            self.revision += 1
            ScanStorage.save(tree: result.tree, errorCount: result.errors)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanner?.cancel()
        isScanning = false
    }

    func navigate(to index: Int) {
        guard let tree else { return }
        guard index >= 0 else {          // centre click: go up one level
            let p = tree.parent(of: current)
            current = p >= 0 ? p : tree.root
            self.revision += 1
            return
        }
        guard tree.isDir(of: index) else { return }
        current = index
        self.revision += 1
    }

    func handleSelect(_ index: Int) {
        guard let tree else { return }
        if tree.isDir(of: index) {
            navigate(to: index)
        } else {
            quickLook(index)
        }
    }

    // MARK: - Volume

    var scannedSize: UInt64 {
        guard let tree else { return 0 }
        return tree.size(of: tree.root)
    }

    // MARK: - Actions

    func showInFinder(_ index: Int) {
        guard let tree else { return }
        let path = tree.path(of: index)
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func quickLook(_ index: Int) {
        guard let tree else { return }
        let path = tree.path(of: index)
        guard !path.isEmpty else { return }
        quickLookURL = URL(fileURLWithPath: path)
    }

    // MARK: - Collector

    func addToCollector(_ index: Int) {
        guard let tree, tree.nodes.indices.contains(index) else { return }   // -1 = empty drag
        guard tree.path(of: index).isEmpty == false else { return }   // skip aggregates
        if !collected.contains(index) { collected.append(index) }
    }

    func addAllToCollector(_ indices: [Int]) {
        for i in indices { addToCollector(i) }
    }

    func clearCollector() { collected = [] }

    var collectedSize: UInt64 {
        guard let tree else { return 0 }
        return collected.reduce(0) { $0 + tree.size(of: $1) }
    }

    func executeDelete() {
        showDeleteConfirmation = false
        guard let tree else { return }

        var deleted: [(index: Int, parent: Int)] = []
        for index in collected {
            let path = tree.path(of: index)
            guard !path.isEmpty else { continue }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                deleted.append((index, tree.parent(of: index)))
            } catch {
                errorCount += 1
            }
        }

        for d in deleted { tree.detach(d.index) }
        // Sizes of the ancestors are updated in place, no rescan needed.
        for d in deleted where d.parent >= 0 { tree.recomputeSize(of: d.parent) }
        self.revision += 1
        collected = []
        if !deleted.isEmpty {
            ScanStorage.save(tree: tree, errorCount: self.errorCount)
        }
    }
}
