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
    @State private var isDropTargeted = false
    @State private var showRenameNode = false
    @State private var renameTitle = ""
    @State private var renameTarget: ProjectNode?
    @State private var selectedContentID: UUID?
    @State private var documentTitle = ""
    @State private var documentBody = ""
    @State private var isEditingMarkdown = false
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
            guard url.scheme == "pkn" else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            // pkn://open alone is the widget's app-launch action; the host is "open".
            guard parts.count >= 2,
                  let projectID = UUID(uuidString: parts[0]),
                  let nodeID = UUID(uuidString: parts[1]) else { return }
            store.open(projectID: projectID, nodeID: nodeID)
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
                    }.frame(minHeight: 420, idealHeight: 460, maxHeight: 460)
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
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                importDroppedFiles(providers, to: node.id)
            }
        } else { ContentUnavailableView("Select a node", systemImage: "point.3.connected.trianglepath.dotted") }
    }

    private let contentKindOrder: [NodeContent.Kind] = [.image, .video, .audio, .markdown, .file, .link]

    private func contentIndex(for node: ProjectNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(contentKindOrder, id: \.self) { kind in
                    let items = node.content.filter { $0.kind == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: symbol(for: kind)).font(.caption).foregroundStyle(.secondary)
                                Text(groupTitle(for: kind)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                Spacer(minLength: 0)
                            }
                            if kind == .image {
                                VStack(spacing: 4) {
                                    ForEach(Array(imageRows(items).enumerated()), id: \.offset) { _, row in
                                        HStack(spacing: 4) {
                                            ForEach(row) { item in
                                                Button { selectContent(item, in: node) } label: {
                                                    ZStack {
                                                        RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.55))
                                                        if let image = NSImage(contentsOf: store.mediaURL(for: item)) {
                                                            Image(nsImage: image).resizable().scaledToFill().frame(height: 48).clipped()
                                                        } else {
                                                            Image(systemName: "photo").foregroundStyle(.secondary).frame(height: 48)
                                                        }
                                                    }
                                                    .frame(maxWidth: .infinity).frame(height: 48).clipShape(RoundedRectangle(cornerRadius: 5))
                                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(isSelected(item, in: node) ? Color.accentColor : Color.clear, lineWidth: 2))
                                                    .contentShape(RoundedRectangle(cornerRadius: 5))
                                                }
                                                .buttonStyle(.plain).help(item.title)
                                                .contextMenu { removeContentButton(item, node: node) }
                                            }
                                            if row.count < 3 { ForEach(0..<(3-row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).frame(height: 48) } }
                                        }
                                    }
                                }
                            } else {
                                ForEach(items) { item in
                                    Button { selectContent(item, in: node) } label: {
                                        HStack(spacing: 7) {
                                            Image(systemName: symbol(for: item.kind)).frame(width: 16).foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title).lineLimit(1).font(.callout)
                                                if item.kind == .image, let note = item.annotation, !note.isEmpty {
                                                    Text(note).lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 7).padding(.vertical, 6)
                                        .background(isSelected(item, in: node) ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { removeContentButton(item, node: node) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 3)
        }
        .scrollIndicators(.visible)
        .frame(maxHeight: .infinity)
        .onAppear { if selectedContentID == nil, let first = node.content.first { selectContent(first, in: node) } }
    }

    private func imageRows(_ items: [NodeContent]) -> [[NodeContent]] {
        stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start..<min(start + 3, items.count)])
        }
    }

    private func importDroppedFiles(_ providers: [NSItemProvider], to nodeID: UUID) -> Bool {
        let candidates = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !candidates.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in candidates {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                if let url, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let files = lock.withLock { urls }
            if !files.isEmpty { store.importItems(files, to: nodeID) }
        }
        return true
    }

    @ViewBuilder private func removeContentButton(_ item: NodeContent, node: ProjectNode) -> some View {
        Button(role: .destructive) {
            store.removeContent(nodeID: node.id, itemID: item.id)
            if selectedContentID == item.id { selectedContentID = nil }
        } label: { Label("Remove from node", systemImage: "minus.circle") }
    }

    private func groupTitle(for kind: NodeContent.Kind) -> String {
        switch kind {
        case .image: "Images"
        case .video: "Videos"
        case .audio: "Audio"
        case .markdown: "Documents"
        case .file: "Files"
        case .link: "Links"
        }
    }

    @ViewBuilder private func contentEditor(for node: ProjectNode) -> some View {
        if let item = selectedItem(in: node) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol(for: item.kind)).foregroundStyle(.secondary)
                    if item.kind != .markdown { Text(item.title).font(.headline).lineLimit(1) }
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
                            .textFieldStyle(.plain).font(.title2.weight(.semibold))
                            .onChange(of: documentTitle) { _, newValue in store.updateDocument(nodeID: node.id, itemID: item.id, title: newValue, body: documentBody) }
                        HStack {
                            Text("Markdown").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(isEditingMarkdown ? "Preview" : "Edit Markdown") { isEditingMarkdown.toggle() }
                                .buttonStyle(.borderless)
                        }
                        Group {
                            if isEditingMarkdown {
                                TextEditor(text: $documentBody)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(6)
                                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                                    .onChange(of: documentBody) { _, newValue in store.updateDocument(nodeID: node.id, itemID: item.id, title: documentTitle, body: newValue) }
                            } else {
                                ScrollView {
                                    MarkdownText(document: documentBody.isEmpty ? "*Empty document*" : documentBody)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                }
                                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
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
            isEditingMarkdown = false
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

private struct MarkdownText: View {
    let document: String

    var body: some View {
        Text((try? AttributedString(markdown: document, options: .init(interpretedSyntax: .full))) ?? AttributedString(document))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
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
