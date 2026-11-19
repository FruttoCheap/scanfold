// Scan cache round trip. From the repo root:
//   swiftc Scanfold/Model/*.swift Tests/main.swift -o build/check && build/check
import Foundation

let tree = FileTree()
tree.setRoot(name: "Data", path: "/System/Volumes/Data")
let users = tree.add(name: "Users", path: "/System/Volumes/Data/Users", allocSize: 0, isDir: true, parent: tree.root)
tree.add(name: "big.mov", path: "/System/Volumes/Data/Users/big.mov", allocSize: 5_000_000, isDir: false, parent: users)
tree.add(name: "Small files (3)", path: "", allocSize: 1_234, isDir: false, isAggregate: true, parent: users)
tree.add(name: "é 日本.txt", path: "/System/Volumes/Data/é 日本.txt", allocSize: 2_000_000, isDir: false, parent: tree.root)
tree.recomputeAllSizes()

let data = ScanStorage.serialize(nodes: tree.nodes, errorCount: 7, date: Date(timeIntervalSince1970: 1_000))
guard let back = ScanStorage.deserialize(data: data) else { fatalError("valid cache rejected") }
precondition(back.tree.nodes == tree.nodes, "nodes changed in the round trip")
precondition(back.errorCount == 7 && back.date.timeIntervalSince1970 == 1_000)
precondition(back.tree.size(of: back.tree.root) == 7_001_234)
precondition(ScanStorage.deserialize(data: data.dropLast()) == nil, "truncated cache accepted")
print("ok")
