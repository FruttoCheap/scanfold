import SwiftUI
import AppKit
import QuickLook
import QuickLookUI
import UniformTypeIdentifiers

/// Drag payload: an index into the scanned tree.
struct NodeRef: Codable, Transferable {
    let index: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .scanfoldNode)
    }
}

extension UTType {
    static let scanfoldNode = UTType(exportedAs: "com.giuliodesana.scanfold.node")
}

/// Sidebar list of the current folder's children, biggest first.
struct SidebarView: View {
    let tree: FileTree
    let current: Int
    let hovered: Int?
    let onOpen: (Int) -> Void
    let onShowInFinder: (Int) -> Void
    let onQuickLook: (Int) -> Void
    let onCollect: (Int) -> Void

    var body: some View {
        List {
            ForEach(children, id: \.self) { child in
                HStack {
                    Image(systemName: icon(for: child))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(tree.name(of: child))
                        .lineLimit(1)
                    if tree.isAggregate(of: child) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(VolumeInfo.fmt(tree.size(of: child)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onOpen(child) }
                .background(child == hovered ? Color.accentColor.opacity(0.12) : Color.clear)
                .draggable(NodeRef(index: child))
                .contextMenu {
                    Button("Open") { onOpen(child) }
                    Button("Add to Collector") { onCollect(child) }
                    Divider()
                    Button("Show in Finder") { onShowInFinder(child) }
                    Button("Quick Look") { onQuickLook(child) }
                }
            }
        }
        .listStyle(.plain)
    }

    private var children: [Int] {
        tree.children(of: current).sorted { tree.size(of: $0) > tree.size(of: $1) }
    }

    private func icon(for index: Int) -> String {
        if tree.isAggregate(of: index) { return "square.stack.3d.up" }
        if tree.isDir(of: index) { return "folder" }
        return "doc"
    }
}

/// Path bar of the current folder: up button, clickable breadcrumb, folder size.
struct BreadcrumbView: View {
    let tree: FileTree
    let current: Int
    let onNavigate: (Int) -> Void   // -1 = go up one level

    var body: some View {
        HStack(spacing: 8) {
            Button { onNavigate(-1) } label: {
                Image(systemName: "chevron.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(current == tree.root)
            .help("Go up to parent folder")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(ancestry.enumerated()), id: \.offset) { i, node in
                            if i > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            let isLast = i == ancestry.count - 1
                            Button { onNavigate(node) } label: {
                                Label(title(i, node), systemImage: i == 0 ? "internaldrive" : "folder")
                                    .lineLimit(1)
                                    .fontWeight(isLast ? .semibold : .regular)
                                    .foregroundStyle(isLast ? .primary : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isLast ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .id(node)
                        }
                    }
                }
                // Deep paths: keep the current folder in view.
                .onAppear { proxy.scrollTo(current, anchor: .trailing) }
                .onChange(of: current) { _, new in proxy.scrollTo(new, anchor: .trailing) }
            }

            Text(VolumeInfo.fmt(tree.size(of: current)))
                .font(.callout.weight(.semibold).monospacedDigit())
            if tree.fileCount(of: current) > 0 {
                Text("\(tree.fileCount(of: current).formatted()) items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var ancestry: [Int] { tree.ancestry(of: current) }

    private func title(_ i: Int, _ node: Int) -> String {
        i == 0 && tree.name(of: node).isEmpty ? tree.path(of: node) : tree.name(of: node)
    }
}

/// Disk usage summary: one capacity bar plus its legend.
struct VolumeInfoView: View {
    let volume: VolumeInfo
    let scanned: UInt64
    let errors: Int

    var body: some View {
        // ponytail: scanned is capped at used, so the three segments always add up to the disk size
        let seen = min(scanned, volume.usedSpace)
        let segments: [(title: String, bytes: UInt64, color: Color)] = [
            ("Scanned", seen, .accentColor),
            ("Not scanned", volume.usedSpace - seen, .gray),
            ("Available", volume.availableCapacity, Color.secondary.opacity(0.25))
        ]
        let total = Double(max(volume.totalCapacity, 1))

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Storage", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("\(volume.formattedUsed) of \(volume.formattedTotal) used")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { i in
                        segments[i].color
                            .frame(width: max(0, geo.size.width - 4) * Double(segments[i].bytes) / total)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())

            HStack(spacing: 18) {
                ForEach(segments.indices, id: \.self) { i in
                    legend(segments[i].title, segments[i].bytes, segments[i].color)
                }
                legend("Purgeable", volume.purgeableSpace, nil)
                    .help("Space macOS can free on its own (caches, snapshots); counted in Used")
                Spacer()
                if errors > 0 {
                    Label("\(errors) unreadable", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func legend(_ title: String, _ bytes: UInt64, _ color: Color?) -> some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(title).foregroundStyle(.secondary)
            Text(VolumeInfo.fmt(bytes)).monospacedDigit()
        }
        .font(.callout)
    }
}

/// Drop target for items to be trashed.
struct CollectorPanel: View {
    let tree: FileTree
    let items: [Int]
    let total: UInt64
    let onClear: () -> Void
    let onDelete: () -> Void
    let onDrop: ([Int]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Collector", systemImage: "tray.and.arrow.down.fill")
                    .font(.headline)
                Text(items.isEmpty ? "Drag folders here to trash them" : "\(items.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !items.isEmpty {
                    Button("Clear", action: onClear)
                }
            }

            if !items.isEmpty {
                List {
                    ForEach(items, id: \.self) { item in
                        HStack {
                            Text(tree.name(of: item)).lineLimit(1)
                            Spacer()
                            Text(VolumeInfo.fmt(tree.size(of: item)))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: 120)

                HStack {
                    Text("Total: \(VolumeInfo.fmt(total))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Move to Trash", role: .destructive, action: onDelete)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: NodeRef.self) { dropped, _ in
            onDrop(dropped.map(\.index))
            return true
        }
    }
}

/// Static scan progress (items so far, current path, errors).
struct ScanProgressView: View {
    let progress: Scanner.Progress?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ProgressView().frame(width: 180)
            if let p = progress {
                Text("Scanned \(p.scanned)")
                    .font(.title2)
                Text(p.currentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if p.errors > 0 {
                    Text("\(p.errors) unreadable")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Button("Cancel", action: onCancel)
        }
        .padding()
    }
}

/// Quick Look preview.
struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}