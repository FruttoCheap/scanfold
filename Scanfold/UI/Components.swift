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

/// Path breadcrumb of the current folder.
struct BreadcrumbView: View {
    let tree: FileTree
    let current: Int
    let onNavigate: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(ancestry.enumerated()), id: \.offset) { i, node in
                    if i > 0 {
                        Text("›").foregroundStyle(.tertiary)
                    }
                    Button(action: { onNavigate(node) }) {
                        Text(i == 0 ? (tree.name(of: node).isEmpty ? tree.path(of: node) : tree.name(of: node))
                                    : tree.name(of: node))
                            .lineLimit(1)
                            .foregroundStyle(i == ancestry.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 30)
    }

    private var ancestry: [Int] { tree.ancestry(of: current) }
}

/// Volume capacity and scan stats.
struct VolumeInfoView: View {
    let volume: VolumeInfo
    let scanned: UInt64
    let hidden: UInt64
    let errors: Int

    var body: some View {
        HStack(spacing: 20) {
            stat("Total", volume.formattedTotal)
            stat("Available", volume.formattedAvailable)
            stat("Used", volume.formattedUsed)
            stat("Purgeable", volume.formattedPurgeable)
            stat("Scanned", VolumeInfo.fmt(scanned))
            stat("Hidden", VolumeInfo.fmt(hidden))
            if errors > 0 {
                Label("\(errors) unreadable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced))
        }
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
                if !items.isEmpty {
                    Text("\(items.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !items.isEmpty {
                    Button("Clear", action: onClear)
                }
            }

            if items.isEmpty {
                Text("Drag folders here to trash them")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
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