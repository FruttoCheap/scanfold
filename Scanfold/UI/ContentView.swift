import SwiftUI
import QuickLook

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if let tree = model.tree {
                SidebarView(
                    tree: tree,
                    current: model.current,
                    hovered: model.hoveredNode,
                    onOpen: { model.navigate(to: $0) },
                    onShowInFinder: { model.showInFinder($0) },
                    onQuickLook: { model.quickLook($0) },
                    onCollect: { model.addToCollector($0) }
                )
            } else {
                ContentUnavailableView("No Data", systemImage: "externaldrive")
            }
        } detail: {
            VStack(spacing: 0) {
                if model.isScanning {
                    ScanProgressView(progress: model.progress, onCancel: model.cancelScan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let tree = model.tree {
                    VStack(spacing: 6) {
                        TreemapView(
                            tree: tree,
                            current: model.current,
                            revision: model.revision,
                            onSelect: { model.handleSelect($0) },
                            onHover: { model.hoveredNode = $0 },
                            onQuickLook: { model.quickLook($0) },
                            onShowInFinder: { model.showInFinder($0) },
                            onCollect: { model.addToCollector($0) }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        TreemapInspectorBar(tree: tree, current: model.current, hovered: model.hoveredNode)
                    }
                    .padding(8)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text("Press Scan to analyse the disk")
                    )
                }

                Divider()

                if let tree = model.tree {
                    HStack(spacing: 0) {
                        if model.canNavigateUp {
                            Button(action: model.navigateUp) {
                                Image(systemName: "chevron.up")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .help("Go up to parent folder")
                        }
                        BreadcrumbView(tree: tree, current: model.current) { model.navigate(to: $0) }
                    }
                    Divider()
                }

                if let volume = model.volumeInfo {
                    VolumeInfoView(
                        volume: volume,
                        scanned: model.scannedSize,
                        hidden: model.hiddenSpace,
                        errors: model.errorCount
                    )
                    .padding(.vertical, 6)
                }

                Divider()

                if let tree = model.tree {
                    CollectorPanel(
                        tree: tree,
                        items: model.collected,
                        total: model.collectedSize,
                        onClear: model.clearCollector,
                        onDelete: { model.showDeleteConfirmation = true },
                        onDrop: { model.addAllToCollector($0) }
                    )
                    .padding(8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if model.isScanning {
                        Button(action: model.cancelScan) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button(action: model.startScan) {
                            Label("Scan", systemImage: "magnifyingglass")
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .alert("Move to Trash?", isPresented: $model.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { model.executeDelete() }
        } message: {
            Text("This moves \(model.collected.count) items to the Trash, total \(VolumeInfo.fmt(model.collectedSize)).")
        }
        .sheet(item: Binding(
            get: { model.quickLookURL.map(IdentifiedURL.init) },
            set: { model.quickLookURL = $0?.url }
        )) { item in
            QuickLookPreview(url: item.url)
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}
