import SwiftUI

/// One folder outline container representing a direct child folder of the current location.
struct FolderContainer: Identifiable {
    let id: Int             // Node index in FileTree (e.g. Downloads)
    let rect: CGRect        // Total bounding rectangle
    let outlineRect: CGRect // Bounded outline path
    let headerRect: CGRect  // Header strip at the top
    let contentRect: CGRect // Inner space where child tiles are placed
    let name: String
    let size: UInt64
    let color: Color
    let branch: Int
}

/// One rectangle of the treemap (a file, leaf folder, or small files aggregate).
struct Tile: Identifiable {
    let id: Int             // Node index in FileTree
    let parentFolderId: Int // Node index of direct child folder (e.g. Downloads), or -1 if at root
    let rect: CGRect
    let depth: Int
    let color: Color
}

/// Result of layout computation containing folder containers and their enclosed tiles.
struct TreemapResult {
    let containers: [FolderContainer]
    let tiles: [Tile]
}

/// Squarified treemap layout (Bruls et al.) with folder outline containers.
enum TreemapLayout {
    static let maxDepth = 4

    static func compute(tree: FileTree, root: Int, size: CGSize) -> TreemapResult {
        guard size.width > 30, size.height > 30, tree.size(of: root) > 0 else {
            return TreemapResult(containers: [], tiles: [])
        }

        let kids = tree.children(of: root).filter { tree.size(of: $0) > 0 }
        guard !kids.isEmpty else {
            let singleTile = Tile(id: root, parentFolderId: -1, rect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), depth: 0, color: Color.hueForBranch(0))
            return TreemapResult(containers: [], tiles: [singleTile])
        }

        let total = Double(kids.reduce(UInt64(0)) { $0 + tree.size(of: $1) })
        guard total > 0 else {
            return TreemapResult(containers: [], tiles: [])
        }

        let canvasRect = CGRect(origin: .zero, size: size)
        let canvasArea = Double(size.width * size.height)

        // Sort top-level children (Downloads, Documents, Desktop, etc.) descending by size
        let sortedKids = kids.sorted { tree.size(of: $0) > tree.size(of: $1) }
        var topItems: [(Int, Double, Int)] = sortedKids.enumerated().map { (index, kid) in
            (kid, Double(tree.size(of: kid)) / total * canvasArea, index)
        }

        var topLevelPlacements: [(Int, CGRect, Int)] = []
        squarifyTopLevel(items: &topItems, in: canvasRect, into: &topLevelPlacements)

        var containers: [FolderContainer] = []
        var tiles: [Tile] = []

        for (itemIdx, itemRect, itemBranch) in topLevelPlacements {
            let isDir = tree.isDir(of: itemIdx)
            let b = itemBranch
            let rect = itemRect
            let folderKids = isDir ? tree.children(of: itemIdx).filter { tree.size(of: $0) > 0 } : []

            // A folder gets an outline container if it has space and children
            if isDir && rect.width >= 56 && rect.height >= 42 && !folderKids.isEmpty {
                let headerHeight: CGFloat = 24
                let outlineRect = rect.insetBy(dx: 2, dy: 2)
                let headerRect = CGRect(x: outlineRect.minX + 2, y: outlineRect.minY + 2,
                                        width: max(0, outlineRect.width - 4), height: headerHeight)
                let contentRect = CGRect(x: outlineRect.minX + 3, y: outlineRect.minY + headerHeight + 3,
                                         width: max(0, outlineRect.width - 6), height: max(0, outlineRect.height - headerHeight - 5))

                let container = FolderContainer(
                    id: itemIdx,
                    rect: rect,
                    outlineRect: outlineRect,
                    headerRect: headerRect,
                    contentRect: contentRect,
                    name: tree.name(of: itemIdx),
                    size: tree.size(of: itemIdx),
                    color: Color.hueForBranch(b),
                    branch: b
                )
                containers.append(container)

                // Layout the contents of this folder inside contentRect
                if contentRect.width > 8 && contentRect.height > 8 {
                    walkSubtree(tree, node: itemIdx, parentFolderId: itemIdx, rect: contentRect, depth: 1, branch: b, into: &tiles)
                }
            } else {
                // Leaf file, empty folder, or too small for container
                let r = rect.insetBy(dx: 1.5, dy: 1.5)
                if r.width > 2 && r.height > 2 {
                    tiles.append(Tile(id: itemIdx, parentFolderId: -1, rect: r, depth: 0, color: Color.hueForBranch(b)))
                }
            }
        }

        return TreemapResult(containers: containers, tiles: tiles)
    }

    /// Squarifies top-level children to divide the canvas among the main folders (Downloads, Documents, Desktop, etc.).
    private static func squarifyTopLevel(items: inout [(Int, Double, Int)], in rect: CGRect, into placements: inout [(Int, CGRect, Int)]) {
        var rect = rect
        while !items.isEmpty {
            let horizontal = rect.width >= rect.height
            let shorter = horizontal ? rect.height : rect.width
            guard shorter > 0.5 else { break }

            var row: [(Int, Double, Int)] = []
            var rowArea = 0.0
            var best = Double.greatestFiniteMagnitude

            while let next = items.first {
                var candidateRow = row
                candidateRow.append(next)
                let candidateArea = rowArea + next.1
                let worst = worstAspectRatio(row: candidateRow, candidateArea: candidateArea, shorter: shorter)

                if row.isEmpty || worst <= best {
                    best = worst
                    row = candidateRow
                    rowArea = candidateArea
                    items.removeFirst()
                } else {
                    break
                }
            }
            guard !row.isEmpty else { break }

            let thickness = rowArea / shorter
            var offset = 0.0
            for (idx, area, b) in row {
                let len = area / thickness
                let r = horizontal
                    ? CGRect(x: rect.minX, y: rect.minY + offset, width: thickness, height: len)
                    : CGRect(x: rect.minX + offset, y: rect.minY, width: len, height: thickness)
                placements.append((idx, r, b))
                offset += len
            }

            if horizontal {
                rect = CGRect(x: rect.minX + thickness, y: rect.minY,
                              width: max(0, rect.width - thickness), height: rect.height)
            } else {
                rect = CGRect(x: rect.minX, y: rect.minY + thickness,
                              width: rect.width, height: max(0, rect.height - thickness))
            }
            if rect.width < 0.5 || rect.height < 0.5 { break }
        }
    }

    /// Evaluates the worst aspect ratio in candidate row according to Bruls et al.
    private static func worstAspectRatio(row: [(Int, Double, Int)], candidateArea: Double, shorter: Double) -> Double {
        guard shorter > 0, candidateArea > 0 else { return Double.greatestFiniteMagnitude }
        let s2 = candidateArea * candidateArea
        let w2 = shorter * shorter
        var worst = 0.0
        for item in row {
            let r = item.1
            guard r > 0 else { continue }
            let ratio = max((w2 * r) / s2, s2 / (w2 * r))
            if ratio > worst { worst = ratio }
        }
        return worst
    }

    /// Subdivides the content area of a folder among its sub-files and subfolders.
    private static func walkSubtree(_ tree: FileTree, node: Int, parentFolderId: Int, rect: CGRect, depth: Int, branch: Int, into tiles: inout [Tile]) {
        let kids = tree.children(of: node).filter { tree.size(of: $0) > 0 }
        guard depth < maxDepth, !kids.isEmpty, rect.width >= 24, rect.height >= 24 else {
            let r = rect.insetBy(dx: 1, dy: 1)
            if r.width > 1 && r.height > 1 {
                tiles.append(Tile(id: node, parentFolderId: parentFolderId, rect: r, depth: depth, color: shade(branch, depth)))
            }
            return
        }
        let total = Double(kids.reduce(UInt64(0)) { $0 + tree.size(of: $1) })
        guard total > 0 else {
            let r = rect.insetBy(dx: 1, dy: 1)
            if r.width > 1 && r.height > 1 {
                tiles.append(Tile(id: node, parentFolderId: parentFolderId, rect: r, depth: depth, color: shade(branch, depth)))
            }
            return
        }
        let canvasArea = Double(rect.width * rect.height)
        var items: [(Int, Double, Int)] = kids.sorted { tree.size(of: $0) > tree.size(of: $1) }
            .map { ($0, Double(tree.size(of: $0)) / total * canvasArea, branch) }
        squarifySubtree(tree, items: &items, parentFolderId: parentFolderId, in: rect, depth: depth, into: &tiles)
    }

    private static func squarifySubtree(_ tree: FileTree, items: inout [(Int, Double, Int)], parentFolderId: Int, in rect: CGRect, depth: Int, into tiles: inout [Tile]) {
        var rect = rect
        while !items.isEmpty {
            let horizontal = rect.width >= rect.height
            let shorter = horizontal ? rect.height : rect.width
            guard shorter > 0.5 else { break }

            var row: [(Int, Double, Int)] = []
            var rowArea = 0.0
            var best = Double.greatestFiniteMagnitude

            while let next = items.first {
                var candidateRow = row
                candidateRow.append(next)
                let candidateArea = rowArea + next.1
                let worst = worstAspectRatio(row: candidateRow, candidateArea: candidateArea, shorter: shorter)

                if row.isEmpty || worst <= best {
                    best = worst
                    row = candidateRow
                    rowArea = candidateArea
                    items.removeFirst()
                } else {
                    break
                }
            }
            guard !row.isEmpty else { break }

            let thickness = rowArea / shorter
            var offset = 0.0
            for (idx, area, b) in row {
                let len = area / thickness
                let r = horizontal
                    ? CGRect(x: rect.minX, y: rect.minY + offset, width: thickness, height: len)
                    : CGRect(x: rect.minX + offset, y: rect.minY, width: len, height: thickness)
                emitSubtree(tree, idx: idx, parentFolderId: parentFolderId, rect: r, depth: depth, branch: b, into: &tiles)
                offset += len
            }

            if horizontal {
                rect = CGRect(x: rect.minX + thickness, y: rect.minY,
                              width: max(0, rect.width - thickness), height: rect.height)
            } else {
                rect = CGRect(x: rect.minX, y: rect.minY + thickness,
                              width: rect.width, height: max(0, rect.height - thickness))
            }
            if rect.width < 0.5 || rect.height < 0.5 { break }
        }
    }

    private static func emitSubtree(_ tree: FileTree, idx: Int, parentFolderId: Int, rect: CGRect, depth: Int, branch: Int, into tiles: inout [Tile]) {
        guard rect.width > 1, rect.height > 1 else { return }
        if tree.isDir(of: idx), depth < maxDepth, !tree.children(of: idx).isEmpty, rect.width >= 24, rect.height >= 24 {
            walkSubtree(tree, node: idx, parentFolderId: parentFolderId, rect: rect, depth: depth + 1, branch: branch, into: &tiles)
        } else {
            let r = rect.insetBy(dx: 1, dy: 1)
            if r.width > 1 && r.height > 1 {
                tiles.append(Tile(id: idx, parentFolderId: parentFolderId, rect: r, depth: depth, color: shade(branch, depth)))
            }
        }
    }

    private static func shade(_ branch: Int, _ depth: Int) -> Color {
        Color.hueForBranch(branch).opacity(max(0.42, 1.0 - Double(depth - 1) * 0.14))
    }
}

extension Color {
    static func hueForBranch(_ index: Int) -> Color {
        let hues: [Double] = [
            0.58, // Blue
            0.08, // Orange
            0.35, // Green
            0.78, // Purple
            0.48, // Teal
            0.02, // Red / Coral
            0.65, // Indigo
            0.14, // Amber
            0.88, // Magenta
            0.43  // Mint
        ]
        return Color(hue: hues[abs(index) % hues.count], saturation: 0.62, brightness: 0.88)
    }
}

/// Block (treemap) view: displays each folder inside the current location with an outline
/// container, and nested files/folders as sized tiles within.
struct TreemapView: View {
    let tree: FileTree
    let current: Int
    let revision: Int
    let onSelect: (Int) -> Void
    let onHover: (Int?) -> Void
    let onQuickLook: (Int) -> Void
    let onShowInFinder: (Int) -> Void
    let onCollect: (Int) -> Void

    @State private var containers: [FolderContainer] = []
    @State private var tiles: [Tile] = []
    @State private var hovered: Int?
    @State private var hoveredParentId: Int?
    @State private var canvasSize: CGSize = .zero
    @State private var layoutID = 0

    var body: some View {
        Canvas { context, _ in
            // 1. Draw Folder Outline Containers
            for container in containers {
                let isHovered = (hovered == container.id) || (hoveredParentId == container.id)
                let outlinePath = Path(roundedRect: container.outlineRect, cornerRadius: 7)

                // Translucent background fill
                context.fill(outlinePath, with: .color(container.color.opacity(isHovered ? 0.20 : 0.08)))

                // Prominent Folder Outline
                if isHovered {
                    context.stroke(outlinePath, with: .color(.white), lineWidth: 2.5)
                } else {
                    context.stroke(outlinePath, with: .color(container.color.opacity(0.85)), lineWidth: 2.0)
                }

                // Header Banner: 📁 FolderName  Size
                let headerPath = Path(roundedRect: container.headerRect, cornerRadius: 5)
                let headerFill = isHovered ? container.color.opacity(0.60) : container.color.opacity(0.35)
                context.fill(headerPath, with: .color(headerFill))

                if container.headerRect.width > 44 {
                    // Size on the right when there is room; the name truncates before it instead of overlapping.
                    let size = context.resolve(
                        Text(VolumeInfo.fmt(container.size))
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.9))
                    )
                    let sizeWidth = container.headerRect.width > 120
                        ? size.measure(in: container.headerRect.size).width + 8 : 0
                    if sizeWidth > 0 {
                        context.draw(size, at: CGPoint(x: container.headerRect.maxX - 6, y: container.headerRect.midY),
                                     anchor: .trailing)
                    }
                    context.draw(
                        Text("\(Image(systemName: "folder.fill")) \(container.name)")
                            .font(.callout.weight(isHovered ? .bold : .semibold))
                            .foregroundColor(.white),
                        in: CGRect(x: container.headerRect.minX + 6, y: container.headerRect.minY + 3,
                                   width: max(0, container.headerRect.width - 12 - sizeWidth), height: 18)
                    )
                }
            }

            // 2. Draw Child Tiles inside the containers
            for tile in tiles {
                let isHovered = tile.id == hovered
                let path = Path(roundedRect: tile.rect, cornerRadius: 4)

                context.fill(path, with: .color(isHovered ? tile.color.opacity(1.0) : tile.color))

                if isHovered {
                    context.stroke(path, with: .color(.white), lineWidth: 2)
                } else {
                    context.stroke(path, with: .color(.black.opacity(0.22)), lineWidth: 0.5)
                }

                // ponytail: only top-level items get a label; nested tiles show the subdivision, hover names them
                if tile.parentFolderId == -1, tile.rect.width > 44, tile.rect.height > 18 {
                    let name = tree.name(of: tile.id)
                    context.draw(
                        Text(name)
                            .font(.caption.weight(isHovered ? .semibold : .medium))
                            .foregroundColor(.white),
                        in: CGRect(x: tile.rect.minX + 5, y: tile.rect.minY + 4, width: tile.rect.width - 10, height: 14)
                    )
                    if tile.rect.height > 34, tile.rect.width > 60 {
                        context.draw(
                            Text(VolumeInfo.fmt(tree.size(of: tile.id)))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.85)),
                            in: CGRect(x: tile.rect.minX + 5, y: tile.rect.minY + 18, width: tile.rect.width - 10, height: 12)
                        )
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let loc):
                // Leaf tiles take precedence
                if let hitTile = tiles.first(where: { $0.rect.contains(loc) }) {
                    if hovered != hitTile.id {
                        hovered = hitTile.id
                        hoveredParentId = hitTile.parentFolderId >= 0 ? hitTile.parentFolderId : nil
                        onHover(hitTile.id)
                    }
                } else if let hitHeader = containers.first(where: { $0.headerRect.contains(loc) }) {
                    if hovered != hitHeader.id {
                        hovered = hitHeader.id
                        hoveredParentId = hitHeader.id
                        onHover(hitHeader.id)
                    }
                } else if let hitContainer = containers.first(where: { $0.rect.contains(loc) }) {
                    if hovered != hitContainer.id {
                        hovered = hitContainer.id
                        hoveredParentId = hitContainer.id
                        onHover(hitContainer.id)
                    }
                } else {
                    if hovered != nil {
                        hovered = nil
                        hoveredParentId = nil
                        onHover(nil)
                    }
                }
            case .ended:
                hovered = nil
                hoveredParentId = nil
                onHover(nil)
            }
        }
        .onTapGesture { loc in
            if let hitTile = tiles.first(where: { $0.rect.contains(loc) }) {
                onSelect(hitTile.id)
            } else if let hitContainer = containers.first(where: { $0.headerRect.contains(loc) || $0.rect.contains(loc) }) {
                onSelect(hitContainer.id)
            }
        }
        .contextMenu {
            if let hit = hovered {
                if tree.isDir(of: hit) {
                    Button("Open Folder") { onSelect(hit) }
                } else {
                    Button("Quick Look") { onQuickLook(hit) }
                }
                Button("Add to Collector") { onCollect(hit) }
                Divider()
                if !tree.path(of: hit).isEmpty {
                    Button("Show in Finder") { onShowInFinder(hit) }
                }
            }
        }
        // Drag the block under the cursor (e.g. into the Collector); -1 = nothing hovered, ignored on drop.
        .draggable(NodeRef(index: hovered ?? -1)) {
            if let h = hovered {
                Label(tree.name(of: h), systemImage: tree.isDir(of: h) ? "folder.fill" : "doc.fill")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        // Tracks layout directly; onChange(of: geo.size) could miss the final window size at launch.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { relayout($0) }
        .onChange(of: current) { _, _ in relayout(canvasSize) }
        .onChange(of: revision) { _, _ in relayout(canvasSize) }
    }

    private func relayout(_ size: CGSize) {
        canvasSize = size
        layoutID += 1
        let id = layoutID
        let snapshot = tree
        let root = current
        Task.detached(priority: .userInitiated) {
            let res = TreemapLayout.compute(tree: snapshot, root: root, size: size)
            await MainActor.run {
                // Layouts run in parallel: a stale one finishing last must not overwrite the newest.
                guard id == self.layoutID else { return }
                self.containers = res.containers
                self.tiles = res.tiles
            }
        }
    }
}

/// Inspection bar shown below the treemap displaying details for the active hovered item.
struct TreemapInspectorBar: View {
    let tree: FileTree
    let current: Int
    let hovered: Int?

    var body: some View {
        HStack(spacing: 8) {
            if let node = hovered {
                Image(systemName: icon(for: node))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(tree.name(of: node))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(VolumeInfo.fmt(tree.size(of: node)))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)

                let currentSize = tree.size(of: current)
                if currentSize > 0 {
                    let pct = Double(tree.size(of: node)) / Double(currentSize) * 100
                    Text(String(format: "(%.1f%%)", pct))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if tree.isDir(of: node) && tree.fileCount(of: node) > 0 {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("\(tree.fileCount(of: node)) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let path = tree.path(of: node)
                if !path.isEmpty {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Text("Hover a block to inspect it, click to open")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private func icon(for index: Int) -> String {
        if tree.isAggregate(of: index) { return "square.stack.3d.up.fill" }
        if tree.isDir(of: index) { return "folder.fill" }
        return "doc.fill"
    }
}
