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
                if !model.hasDiskAccess {
                    HStack {
                        Label("Scanfold needs Full Disk Access to see every folder. Turn it on for Scanfold in System Settings, then reopen the app.",
                              systemImage: "lock.shield")
                        Spacer()
                        Button("Open System Settings", action: model.openDiskAccessSettings)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.15))
                    Divider()
                }

                if model.scanIsStale && !model.isScanning, let date = model.scanDate {
                    HStack {
                        Label("This scan is from \(date, style: .relative) ago and may be out of date.",
                              systemImage: "clock.badge.exclamationmark")
                        Spacer()
                        Button("Scan Again", action: model.startScan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.yellow.opacity(0.15))
                    Divider()
                }

                // Path on top, then map, collector, and the disk summary at the bottom.
                if let tree = model.tree {
                    BreadcrumbView(tree: tree, current: model.current) { model.navigate(to: $0) }
                    Divider()
                }

                VStack(spacing: 8) {
                    if model.isScanning {
                        ScanProgressView(progress: model.progress, onCancel: model.cancelScan)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let tree = model.tree {
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
                    } else {
                        Button(action: model.startScan) {
                            Text("Scan").font(.largeTitle).padding(.horizontal, 24)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if let tree = model.tree {
                        CollectorPanel(
                            tree: tree,
                            items: model.collected,
                            total: model.collectedSize,
                            onClear: model.clearCollector,
                            onDelete: { model.showDeleteConfirmation = true },
                            onDrop: { model.addAllToCollector($0) }
                        )
                    }

                    if let volume = model.volumeInfo {
                        VolumeInfoView(volume: volume, scanned: model.scannedSize, errors: model.errorCount)
                    }
                }
                .padding(8)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(model.isScanning ? "Stop" : "Scan", action: model.isScanning ? model.cancelScan : model.startScan)
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
