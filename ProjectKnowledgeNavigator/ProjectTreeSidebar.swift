import SwiftUI
import AppKit
import CrossProjectComponents

/// Adapter boundary: the domain ProjectNode stays independent of the shared UI package.
struct ProjectTreeItem: TreeNodeRepresentable {
    let value: ProjectNode
    var treeID: UUID { value.id }
    var treeTitle: String { value.title }
    var treeChildren: [ProjectTreeItem] { value.children.map(ProjectTreeItem.init) }

    init(_ value: ProjectNode) { self.value = value }
}

/// App shell for the shared Tree component: project controls, storage adapters and keyboard shortcuts.
struct ProjectTreeSidebar: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var isTreeEditingActive: Bool
    let onCreateProject: () -> Void
    @State private var searchText = ""
    @State private var editingNodeID: UUID?
    @State private var selectedNodeIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                Picker("Current project", selection: Binding(
                    get: { store.selectedProjectID },
                    set: { isTreeEditingActive = false; store.selectProject($0) }
                )) {
                    ForEach(store.projects) { project in Text(project.name).tag(project.id) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Button { isTreeEditingActive = false; onCreateProject() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create project")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, ProjectLayoutMetrics.sidebarTopSectionInset)

            Divider()

            HStack(spacing: 6) {
                TextField("Search nodes", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .simultaneousGesture(TapGesture().onEnded { isTreeEditingActive = false })

                Button {
                    isTreeEditingActive = false
                    store.addChild(to: store.selectedNodeID)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a child node to the selected node")
            }
            .padding(10)

            ZStack {
                TreeView(
                    root: ProjectTreeItem(store.manifest.root),
                    selection: Binding(
                        get: { store.selectedNodeID },
                        set: { id in
                            guard let id, let node = store.manifest.root.node(id: id) else { return }
                            store.select(node)
                        }
                    ),
                    expandedIDs: Binding(
                        get: { store.expandedNodeIDs },
                        set: { store.expandedNodeIDs = $0 }
                    ),
                    editingID: $editingNodeID,
                    selectedIDs: $selectedNodeIDs,
                    searchText: searchText,
                    rowHeight: { item, _ in ProjectTreeRowMetrics.rowHeight(for: item.value) },
                    disclosureCenterOffset: { item, _ in ProjectTreeRowMetrics.titleLineCenter(for: item.value) },
                    canMove: { sourceID, targetID, placement in
                        var candidate = store.manifest.root
                        return candidate.moveNode(id: sourceID, to: targetID, placement: Self.modelPlacement(placement))
                    },
                    onMove: { sourceID, targetID, placement in
                        isTreeEditingActive = false
                        _ = store.moveNode(id: sourceID, to: targetID, placement: Self.modelPlacement(placement))
                    },
                    onCreateSibling: { id in store.addSibling(after: id) },
                    onRename: { id, title in
                        guard let node = store.manifest.root.node(id: id) else { return }
                        store.rename(node, to: title)
                    },
                    contentCount: { $0.value.content.count },
                    onDelete: { ids in
                        isTreeEditingActive = false
                        _ = store.deleteNodes(ids: ids)
                        selectedNodeIDs = []
                        editingNodeID = nil
                    },
                    onIndent: { ids in
                        isTreeEditingActive = false
                        _ = store.indentNodes(ids: ids)
                    },
                    onOutdent: { ids in
                        isTreeEditingActive = false
                        _ = store.outdentNodes(ids: ids)
                    },
                    canUndo: store.canUndoTreeChange,
                    canRedo: store.canRedoTreeChange,
                    onUndo: { isTreeEditingActive = false; store.undoTreeChange() },
                    onRedo: { isTreeEditingActive = false; store.redoTreeChange() },
                    onRowInteraction: { _ in isTreeEditingActive = true },
                    interactiveHitTest: { item, point, size in
                        ProjectTreeRowMetrics.isInteractive(node: item.value, point: point, size: size)
                    },
                    rowContent: { context in
                        ProjectTreeRow(context: context, mediaURL: { store.mediaURL(for: $0) })
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !store.manifest.root.containsNodeTitle(matching: searchText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Text("No matching nodes")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 270)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static func modelPlacement(_ placement: TreeMovePlacement) -> NodeMovePlacement {
        switch placement {
        case .before: return .before
        case .inside: return .inside
        case .after: return .after
        }
    }
}

private extension ProjectNode {
    func containsNodeTitle(matching query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || children.contains { $0.containsNodeTitle(matching: query) }
    }
}
