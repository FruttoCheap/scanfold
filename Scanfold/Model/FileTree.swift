import Foundation

/// A node in the scanned tree.
///
/// Children are held in a flat array inside the owning tree and referenced by
/// index: with millions of files, per-node object graphs cost far more ARC
/// traffic and RAM than a struct array.
final class FileTree {
    struct Node {
        var name: String
        var path: String
        var allocSize: UInt64
        var privateSize: UInt64
        var parent: Int      // -1 for root
        var firstChild: Int   // -1 if none
        var lastChild: Int    // -1 if none
        var nextSibling: Int  // -1 if none
        var childCount: Int
        var fileCount: Int
        var isDir: Bool
        var isAggregate: Bool
    }

    private(set) var nodes: [Node]
    let root: Int = 0
    private var lock = os_unfair_lock_s()

    init() {
        nodes = [Node(name: "", path: "", allocSize: 0, privateSize: 0, parent: -1,
                      firstChild: -1, lastChild: -1, nextSibling: -1, childCount: 0, fileCount: 0,
                      isDir: true, isAggregate: false)]
    }

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// Renames the root node.
    func setRoot(name: String, path: String) {
        nodes[0].name = name
        nodes[0].path = path
    }

    /// Creates a node and links it as the last child of `parent`.
    @discardableResult
    func add(name: String, path: String, allocSize: UInt64, privateSize: UInt64 = 0,
             isDir: Bool, isAggregate: Bool = false, parent: Int) -> Int {
        os_unfair_lock_lock(&lock)
        let idx = nodes.count
        nodes.append(Node(name: name, path: path, allocSize: allocSize, privateSize: privateSize,
                           parent: parent, firstChild: -1, lastChild: -1, nextSibling: -1, childCount: 0,
                           fileCount: isDir ? 0 : 1,
                           isDir: isDir, isAggregate: isAggregate))
        if parent >= 0 { link(idx, to: parent) }
        os_unfair_lock_unlock(&lock)
        return idx
    }

    /// Appends `child` to the end of `parent`'s child chain in O(1).
    func link(_ child: Int, to parent: Int) {
        guard parent >= 0, child >= 0 else { return }
        nodes[child].parent = parent
        let last = nodes[parent].lastChild
        if last < 0 {
            nodes[parent].firstChild = child
        } else {
            nodes[last].nextSibling = child
        }
        nodes[parent].lastChild = child
        nodes[parent].childCount += 1
    }

    var childIndices: [Int] {
        get {
            var out: [Int] = []
            var c = nodes[root].firstChild
            while c >= 0 { out.append(c); c = nodes[c].nextSibling }
            return out
        }
    }

    func children(of index: Int) -> [Int] {
        var out: [Int] = []
        var c = nodes[index].firstChild
        while c >= 0 { out.append(c); c = nodes[c].nextSibling }
        return out
    }

    func parent(of index: Int) -> Int { nodes[index].parent }

    func name(of index: Int) -> String { nodes[index].name }
    func path(of index: Int) -> String { nodes[index].path }
    func size(of index: Int) -> UInt64 { nodes[index].allocSize }
    func privateSize(of index: Int) -> UInt64 { nodes[index].privateSize }
    func isDir(of index: Int) -> Bool { nodes[index].isDir }
    func isAggregate(of index: Int) -> Bool { nodes[index].isAggregate }
    func fileCount(of index: Int) -> Int { nodes[index].fileCount }

    /// Recomputes every directory size bottom up. Children always have a
    /// higher index than their parent, so one reverse pass is enough.
    func recomputeAllSizes() {
        var i = nodes.count - 1
        while i >= 0 {
            if nodes[i].isDir {
                var total: UInt64 = 0
                var priv: UInt64 = 0
                var files = 0
                var c = nodes[i].firstChild
                while c >= 0 {
                    total += nodes[c].allocSize
                    priv += nodes[c].privateSize
                    files += nodes[c].fileCount
                    c = nodes[c].nextSibling
                }
                nodes[i].allocSize = total
                nodes[i].privateSize = priv
                nodes[i].fileCount = files
            }
            i -= 1
        }
    }

    /// Recomputes sizes of `index` and all its ancestors, in place.
    func recomputeSize(of index: Int) {
        var current = index
        while current >= 0 {
            if nodes[current].isDir {
                var total: UInt64 = 0
                var priv: UInt64 = 0
                var files = 0
                var c = nodes[current].firstChild
                while c >= 0 {
                    total += nodes[c].allocSize
                    priv += nodes[c].privateSize
                    files += nodes[c].fileCount
                    c = nodes[c].nextSibling
                }
                nodes[current].allocSize = total
                nodes[current].privateSize = priv
                nodes[current].fileCount = files
            }
            current = nodes[current].parent
        }
    }

    /// Removes a node from its parent, detaching it from the sibling chain.
    func detach(_ index: Int) {
        let p = nodes[index].parent
        guard p >= 0 else { return }
        var prev = -1
        var c = nodes[p].firstChild
        while c >= 0 {
            if c == index {
                let nxt = nodes[c].nextSibling
                if prev < 0 {
                    nodes[p].firstChild = nxt
                } else {
                    nodes[prev].nextSibling = nxt
                }
                if nodes[p].lastChild == index {
                    nodes[p].lastChild = prev
                }
                break
            }
            prev = c
            c = nodes[c].nextSibling
        }
        nodes[p].childCount -= 1
        nodes[index].parent = -1
        nodes[index].nextSibling = -1
    }

    /// Path of ancestors from root down to (and including) `index`.
    func ancestry(of index: Int) -> [Int] {
        var out: [Int] = []
        var c = index
        while c >= 0 { out.append(c); c = nodes[c].parent }
        return out.reversed()
    }
}
