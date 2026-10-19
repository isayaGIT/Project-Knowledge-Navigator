import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var searchText = ""
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var importTargetNodeID: UUID?
    @State private var isImportingItems = false
    @State private var showRenameNode = false
    @State private var renameTitle = ""
    @State private var renameTarget: ProjectNode?
    @State private var selectedContentID: UUID?
    @State private var documentTitle = ""
    @State private var documentBody = ""
    @State private var imageAnnotation = ""
    @State private var showAddLink = false
    @State private var linkTitle = ""
    @State private var linkURL = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                    Picker("Current project", selection: Binding(get: { store.selectedProjectID }, set: { store.selectProject($0) })) {
                        ForEach(store.projects) { project in Text(project.name).tag(project.id) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                    Button { showNewProject = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("Create project")
                }.padding(.horizontal, 12).padding(.vertical, 10)
                Divider()
                HStack(spacing: 6) {
                    TextField("Search nodes", text: $searchText).textFieldStyle(.roundedBorder)
                    Button { store.addChild(to: store.selectedNodeID) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("Add a child node to the selected node")
                }.padding(10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        NodeTreeRow(node: store.manifest.root, depth: 0, searchText: searchText)
                    }.padding(.horizontal, 8).padding(.vertical, 6)
                }
            }.frame(minWidth: 270)
        } detail: { detailView }
        .navigationTitle(store.manifest.name)
        .onChange(of: store.selectedNodeID) { _, _ in selectedContentID = nil }
        .onChange(of: store.selectedProjectID) { _, _ in selectedContentID = nil }
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
        .alert("Rename Node", isPresented: $showRenameNode) {
            TextField("Node name", text: $renameTitle)
            Button("Save") { if let target = renameTarget { store.rename(target, to: renameTitle) }; renameTarget = nil }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Add Link", isPresented: $showAddLink) {
            TextField("Title (optional)", text: $linkTitle)
            TextField("https://…", text: $linkURL)
            Button("Add") {
                if let id = store.selectedNodeID { store.addLink(to: id, title: linkTitle, url: linkURL) }
                linkTitle = ""; linkURL = ""
            }
            Button("Cancel", role: .cancel) { linkTitle = ""; linkURL = "" }
        }
        .fileImporter(isPresented: $isImportingItems, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, let target = importTargetNodeID { store.importItems(urls, to: target) }
            importTargetNodeID = nil
        }
    }

    @ViewBuilder private var detailView: some View {
        if let id = store.selectedNodeID, let node = store.manifest.root.node(id: id) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(node.title).font(.largeTitle.weight(.semibold))
                        Button { renameTarget = node; renameTitle = node.title; showRenameNode = true } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Rename node")
                    }
                    Text("\(node.children.count) child nodes · \(node.content.count) content items").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Contents").font(.headline)
                    Spacer()
                    Menu {
                        Button { store.addDocument(to: node.id); selectedContentID = store.manifest.root.node(id: node.id)?.content.last?.id } label: { Label("New Document", systemImage: "doc.text") }
                        Button { importTargetNodeID = node.id; isImportingItems = true } label: { Label("Import Files & Media…", systemImage: "paperclip") }
                        Button { showAddLink = true } label: { Label("Add Link…", systemImage: "link") }
                    } label: { Label("Add Content", systemImage: "plus") }
                }
                if !node.content.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        contentIndex(for: node)
                            .frame(width: 205)
                        Divider()
                        contentEditor(for: node)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(minHeight: 320, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No content yet", systemImage: "doc.richtext", description: Text("Add a document, image, file, audio, video, or link to this node."))
                        .frame(maxWidth: .infinity, minHeight: 180)
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
                Spacer(minLength: 0)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else { ContentUnavailableView("Select a node", systemImage: "point.3.connected.trianglepath.dotted") }
    }

    private func contentIndex(for node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(node.content) { item in
                Button { selectContent(item, in: node) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: item.kind)).frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(1).font(.callout)
                            if item.kind == .image, let note = item.annotation, !note.isEmpty {
                                Text(note).lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(isSelected(item, in: node) ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                .contextMenu { Button(role: .destructive) { store.removeContent(nodeID: node.id, itemID: item.id); if selectedContentID == item.id { selectedContentID = nil } } label: { Label("Remove from node", systemImage: "minus.circle") } }
            }
        }
        .onAppear { if selectedContentID == nil, let first = node.content.first { selectContent(first, in: node) } }
    }

    @ViewBuilder private func contentEditor(for node: ProjectNode) -> some View {
        if let item = selectedItem(in: node) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol(for: item.kind)).foregroundStyle(.secondary)
                    Text(item.title).font(.headline).lineLimit(1)
                    Spacer()
                    if item.kind == .link {
                        Button("Open Link") { if let url = URL(string: item.path) { NSWorkspace.shared.open(url) } }
                    } else if item.kind == .file || item.kind == .audio || item.kind == .video {
                        Button("Open File") { NSWorkspace.shared.open(store.mediaURL(for: item)) }
                    }
                }
                switch item.kind {
                case .image:
                    imageEditor(item, nodeID: node.id)
                case .markdown:
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Document title", text: $documentTitle)
                            .textFieldStyle(.roundedBorder).font(.title3)
                        TextEditor(text: $documentBody)
                            .font(.system(.body, design: .monospaced))
                            .padding(6)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                            .onChange(of: documentBody) { _, newValue in store.updateDocument(nodeID: node.id, itemID: item.id, title: documentTitle, body: newValue) }
                            .onChange(of: documentTitle) { _, newValue in store.updateDocument(nodeID: node.id, itemID: item.id, title: newValue, body: documentBody) }
                        Text("Markdown · changes save locally").font(.caption).foregroundStyle(.secondary)
                    }
                case .link:
                    ContentUnavailableView(item.path, systemImage: "link", description: Text("External link attached to this node."))
                case .audio:
                    ContentUnavailableView(item.title, systemImage: "waveform", description: Text("Open the audio file in your preferred player."))
                case .video:
                    ContentUnavailableView(item.title, systemImage: "play.rectangle", description: Text("Open the video file to preview it."))
                case .file:
                    ContentUnavailableView(item.title, systemImage: "doc", description: Text(store.mediaURL(for: item).lastPathComponent))
                }
                Spacer(minLength: 0)
            }
            .onAppear { selectContent(item, in: node) }
            .onChange(of: item.id) { _, _ in selectContent(item, in: node) }
        } else {
            ContentUnavailableView("Choose content", systemImage: "doc.text.magnifyingglass", description: Text("Select a document, image, or attachment from the list."))
        }
    }

    private func imageEditor(_ item: NodeContent, nodeID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.35))
                    if let image = NSImage(contentsOf: store.mediaURL(for: item)) {
                        Image(nsImage: image).resizable().scaledToFit().padding(8)
                    } else {
                        ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text(store.mediaURL(for: item).lastPathComponent))
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }.frame(minHeight: 220, maxHeight: .infinity)
            Text("Annotation").font(.headline)
            TextEditor(text: $imageAnnotation)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 125)
                .padding(6)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: imageAnnotation) { _, newValue in store.updateAnnotation(nodeID: nodeID, itemID: item.id, annotation: newValue) }
            Text("Notes are saved with this image in the current node.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { imageAnnotation = item.annotation ?? "" }
        .onChange(of: item.id) { _, _ in imageAnnotation = item.annotation ?? "" }
    }

    private func selectContent(_ item: NodeContent, in node: ProjectNode) {
        selectedContentID = item.id
        if item.kind == .markdown {
            documentTitle = item.title
            documentBody = store.documentBody(for: item)
        }
        if item.kind == .image { imageAnnotation = item.annotation ?? "" }
    }
    private func selectedItem(in node: ProjectNode) -> NodeContent? {
        if let id = selectedContentID, let item = node.content.first(where: { $0.id == id }) { return item }
        return node.content.first
    }
    private func isSelected(_ item: NodeContent, in node: ProjectNode) -> Bool { (selectedContentID ?? node.content.first?.id) == item.id }
    private func symbol(for kind: NodeContent.Kind) -> String {
        switch kind {
        case .markdown: "doc.text"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "play.rectangle"
        case .link: "link"
        case .file: "doc"
        }
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
                    if !node.content.isEmpty { Text("\(node.content.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
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
