import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var searchText = ""
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var imageImportNodeID: UUID?
    @State private var isImportingImages = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "square.stack.3d.up"); Text("Projects").font(.headline); Spacer()
                    Button { showNewProject = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("Create project")
                }.padding(.horizontal, 14).padding(.vertical, 12)
                Picker("Current project", selection: Binding(get: { store.selectedProjectID }, set: { store.selectProject($0) })) {
                    ForEach(store.projects) { project in Text(project.name).tag(project.id) }
                }.labelsHidden().padding(.horizontal, 10).padding(.bottom, 8)
                Divider()
                TextField("Search nodes", text: $searchText).textFieldStyle(.roundedBorder).padding(10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        NodeTreeRow(node: store.manifest.root, depth: 0, searchText: searchText)
                    }.padding(.horizontal, 8).padding(.vertical, 6)
                }
            }.frame(minWidth: 270)
        } detail: { detailView }
        .navigationTitle(store.manifest.name)
        .onOpenURL { url in
            let parts = url.pathComponents.filter { $0 != "/" }
            if url.scheme == "pkn", parts.count >= 2,
               let projectID = UUID(uuidString: parts[0]), let nodeID = UUID(uuidString: parts[1]) {
                store.open(projectID: projectID, nodeID: nodeID)
            }
        }
        .alert("New Project", isPresented: $showNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") { store.createProject(named: newProjectName); newProjectName = "" }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        } message: { Text("Each project has its own independent node structure and local data.") }
        .fileImporter(isPresented: $isImportingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, let target = imageImportNodeID { store.importImages(urls, to: target) }
            imageImportNodeID = nil
        }
    }

    @ViewBuilder private var detailView: some View {
        if let id = store.selectedNodeID, let node = store.manifest.root.node(id: id) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PROJECT NODE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(node.title).font(.largeTitle.weight(.semibold))
                    Text("\(node.children.count) child nodes · \(node.content.count) content items").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Content").font(.headline)
                    Spacer()
                    Button { imageImportNodeID = node.id; isImportingImages = true } label: { Label("Add Images", systemImage: "photo.badge.plus") }
                }
                if !node.images.isEmpty {
                    FilmstripScrubber(items: node.images, mediaURL: store.mediaURL(for:)).frame(height: 110)
                }
                if !node.children.isEmpty {
                    Text("Children").font(.headline)
                    ForEach(node.children) { child in
                        Button { store.select(child) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up"); Text(child.title); Spacer()
                                Image(systemName: "arrow.up.left").foregroundStyle(.tertiary)
                            }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                if node.content.isEmpty && node.children.isEmpty {
                    ContentUnavailableView("Empty node", systemImage: "square.stack.3d.up", description: Text("Add children or attach documents and media to this node."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Spacer(minLength: 0)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else { ContentUnavailableView("Select a node", systemImage: "point.3.connected.trianglepath.dotted") }
    }
}

private struct NodeTreeRow: View {
    @EnvironmentObject private var store: ProjectStore
    let node: ProjectNode
    let depth: Int
    let searchText: String
    private var matches: Bool { searchText.isEmpty || node.title.localizedCaseInsensitiveContains(searchText) }
    private var isExpanded: Bool { store.expandedNodeIDs.contains(node.id) }
    private var isSelected: Bool { store.selectedNodeID == node.id }

    var body: some View {
        if matches || node.children.contains(where: { $0.title.localizedCaseInsensitiveContains(searchText) }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !node.children.isEmpty {
                        Button { store.toggleExpanded(node) } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 12, height: 20)
                        }.buttonStyle(.plain)
                    } else { Color.clear.frame(width: 12, height: 20) }
                    Image(systemName: node.children.isEmpty ? "doc.text" : "folder").foregroundStyle(.secondary).frame(width: 16)
                    Text(node.title).lineLimit(1); Spacer(minLength: 0)
                    if !node.images.isEmpty { Text("\(node.images.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle()).padding(.horizontal, 7).padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .onTapGesture { store.select(node) }
                if !node.images.isEmpty {
                    FilmstripScrubber(items: node.images, mediaURL: store.mediaURL(for:)).frame(height: 44).padding(.leading, 18).padding(.bottom, 3)
                }
                if isExpanded || !searchText.isEmpty {
                    ForEach(node.children) { child in NodeTreeRow(node: child, depth: depth + 1, searchText: searchText) }
                }
            }.padding(.leading, depth == 0 ? 0 : 14)
        }
    }
}
