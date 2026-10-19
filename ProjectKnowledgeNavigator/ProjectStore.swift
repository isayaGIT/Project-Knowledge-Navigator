import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProjectSummary: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
}

private struct ProjectCatalog: Codable {
    var projects: [ProjectSummary]
    var selectedProjectID: UUID
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var manifest: ProjectManifest
    @Published private(set) var projects: [ProjectSummary]
    @Published private(set) var selectedProjectID: UUID
    @Published var selectedNodeID: UUID?
    @Published var expandedNodeIDs: Set<UUID>

    private let rootDirectory: URL
    private let catalogURL: URL
    private let syncWidgetDefaults: Bool
    private var projectsDirectory: URL { rootDirectory.appendingPathComponent("Projects", isDirectory: true) }
    var projectFilesDirectoryURL: URL {
        rootDirectory.appendingPathComponent("ProjectFiles", isDirectory: true).appendingPathComponent(manifest.projectID.uuidString, isDirectory: true)
    }
    var mediaDirectoryURL: URL { projectFilesDirectoryURL.appendingPathComponent("Media", isDirectory: true) }
    var documentsDirectoryURL: URL { projectFilesDirectoryURL.appendingPathComponent("Documents", isDirectory: true) }

    init(rootDirectory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProjectKnowledgeNavigator", isDirectory: true)
        self.rootDirectory = rootDirectory ?? support
        self.catalogURL = (rootDirectory ?? support).appendingPathComponent("projects.json")
        self.syncWidgetDefaults = rootDirectory == nil

        let loadedProjects: [ProjectSummary]
        let loadedProjectID: UUID
        let loadedManifest: ProjectManifest
        if let data = try? Data(contentsOf: self.catalogURL),
           let catalog = try? JSONDecoder().decode(ProjectCatalog.self, from: data),
           let selected = catalog.projects.first(where: { $0.id == catalog.selectedProjectID }),
           let projectData = try? Data(contentsOf: (rootDirectory ?? support).appendingPathComponent("Projects/\(selected.id.uuidString).json")),
           let decoded = try? JSONDecoder().decode(ProjectManifest.self, from: projectData) {
            loadedProjects = catalog.projects
            loadedProjectID = selected.id
            loadedManifest = decoded
        } else {
            let initial = ProjectManifest.sample()
            loadedProjects = [ProjectSummary(id: initial.projectID, name: initial.name)]
            loadedProjectID = initial.projectID
            loadedManifest = initial
        }
        self.projects = loadedProjects
        self.selectedProjectID = loadedProjectID
        self.manifest = loadedManifest
        let selectedNode = loadedManifest.selectedNodeID ?? loadedManifest.root.id
        self.selectedNodeID = selectedNode
        self.expandedNodeIDs = Self.ancestorIDs(in: loadedManifest.root, target: selectedNode)
        persistCurrent()
        persistCatalog()
    }

    func select(_ node: ProjectNode) { selectedNodeID = node.id; save() }
    func toggleExpanded(_ node: ProjectNode) {
        if expandedNodeIDs.contains(node.id) { expandedNodeIDs.remove(node.id) }
        else { expandedNodeIDs.insert(node.id) }
    }

    func createProject(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        persistCurrent()
        let root = ProjectNode(title: name)
        let next = ProjectManifest(projectID: UUID(), name: name, root: root, selectedNodeID: root.id)
        projects.append(ProjectSummary(id: next.projectID, name: name))
        selectedProjectID = next.projectID
        manifest = next
        selectedNodeID = root.id
        expandedNodeIDs = [root.id]
        persistCurrent(); persistCatalog()
    }

    func selectProject(_ id: UUID) {
        guard id != selectedProjectID,
              let summary = projects.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: manifestURL(for: summary.id)),
              let next = try? JSONDecoder().decode(ProjectManifest.self, from: data) else { return }
        persistCurrent()
        selectedProjectID = id
        manifest = next
        selectedNodeID = next.selectedNodeID ?? next.root.id
        expandedNodeIDs = Self.ancestorIDs(in: next.root, target: selectedNodeID ?? next.root.id)
        persistCatalog()
    }

    func open(projectID: UUID, nodeID: UUID) {
        if projectID != selectedProjectID { selectProject(projectID) }
        guard let target = manifest.root.node(id: nodeID) else { return }
        selectedNodeID = target.id
        expandedNodeIDs = Self.ancestorIDs(in: manifest.root, target: target.id)
        save()
    }

    func addChild(to parentID: UUID?) {
        let parent = parentID ?? manifest.root.id
        let child = ProjectNode(title: "New Node")
        _ = manifest.root.updateNode(id: parent) { $0.children.append(child) }
        expandedNodeIDs.insert(parent); selectedNodeID = child.id; save()
    }

    func rename(_ node: ProjectNode, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = manifest.root.updateNode(id: node.id) { $0.title = title }
        if node.id == manifest.root.id {
            manifest.name = title
            if let index = projects.firstIndex(where: { $0.id == selectedProjectID }) { projects[index].name = title }
        }
        save()
    }

    func addDocument(to nodeID: UUID) {
        do {
            try FileManager.default.createDirectory(at: documentsDirectoryURL, withIntermediateDirectories: true)
            let id = UUID()
            let filename = "Document-\(id.uuidString).md"
            let destination = documentsDirectoryURL.appendingPathComponent(filename)
            try "# New Document\n\n".write(to: destination, atomically: true, encoding: .utf8)
            let item = NodeContent(id: id, kind: .markdown, title: "New Document", path: relativePath(for: destination))
            _ = manifest.root.updateNode(id: nodeID) { $0.content.append(item) }
            save()
        } catch { assertionFailure("Could not create document: \(error)") }
    }

    func importItems(_ urls: [URL], to nodeID: UUID) {
        guard !urls.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: documentsDirectoryURL, withIntermediateDirectories: true)
            var imported: [NodeContent] = []
            for source in urls {
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                let ext = source.pathExtension
                let type = UTType(filenameExtension: ext)
                let kind: NodeContent.Kind
                if type?.conforms(to: .image) == true { kind = .image }
                else if type?.conforms(to: .audio) == true { kind = .audio }
                else if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true { kind = .video }
                else if ["md", "markdown", "txt", "rtf"].contains(ext.lowercased()) { kind = .markdown }
                else { kind = .file }
                let folder = kind == .markdown ? documentsDirectoryURL : mediaDirectoryURL
                let filename = "\(UUID().uuidString)-\(source.lastPathComponent)"
                let destination = folder.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: source, to: destination)
                imported.append(NodeContent(kind: kind, title: source.deletingPathExtension().lastPathComponent, path: relativePath(for: destination)))
            }
            _ = manifest.root.updateNode(id: nodeID) { $0.content.append(contentsOf: imported) }
            save()
        } catch { assertionFailure("Could not import content: \(error)") }
    }

    func addLink(to nodeID: UUID, title rawTitle: String, url rawURL: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        let item = NodeContent(kind: .link, title: title.isEmpty ? value : title, path: url.absoluteString)
        _ = manifest.root.updateNode(id: nodeID) { $0.content.append(item) }
        save()
    }

    func updateAnnotation(nodeID: UUID, itemID: UUID, annotation: String) {
        _ = manifest.root.updateNode(id: nodeID) { node in
            guard let index = node.content.firstIndex(where: { $0.id == itemID }) else { return }
            node.content[index].annotation = annotation
        }
        save()
    }

    func updateDocument(nodeID: UUID, itemID: UUID, title rawTitle: String, body: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let node = manifest.root.node(id: nodeID), let item = node.content.first(where: { $0.id == itemID }), item.kind == .markdown else { return }
        do {
            try body.write(to: mediaURL(for: item), atomically: true, encoding: .utf8)
            _ = manifest.root.updateNode(id: nodeID) { current in
                guard let index = current.content.firstIndex(where: { $0.id == itemID }) else { return }
                if !title.isEmpty { current.content[index].title = title }
            }
            save()
        } catch { assertionFailure("Could not save document: \(error)") }
    }

    func documentBody(for item: NodeContent) -> String {
        (try? String(contentsOf: mediaURL(for: item), encoding: .utf8)) ?? ""
    }

    func removeContent(nodeID: UUID, itemID: UUID) {
        _ = manifest.root.updateNode(id: nodeID) { $0.content.removeAll { $0.id == itemID } }
        save()
    }

    private func relativePath(for url: URL) -> String {
        let base = rootDirectory.path.hasSuffix("/") ? rootDirectory.path : rootDirectory.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.path
    }

    func mediaURL(for item: NodeContent) -> URL {
        if item.path.hasPrefix("/") { return URL(fileURLWithPath: item.path) }
        return rootDirectory.appendingPathComponent(item.path)
    }

    func save() {
        manifest.selectedNodeID = selectedNodeID
        persistCurrent(); persistCatalog()
    }

    private func manifestURL(for id: UUID) -> URL { projectsDirectory.appendingPathComponent("\(id.uuidString).json") }
    private func persistCurrent() {
        do {
            try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: manifestURL(for: manifest.projectID), options: .atomic)
        } catch { assertionFailure("Could not persist project: \(error)") }
    }
    private func persistCatalog() {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let catalog = ProjectCatalog(projects: projects, selectedProjectID: selectedProjectID)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
        } catch { assertionFailure("Could not persist project catalog: \(error)") }
    }
    private static func ancestorIDs(in root: ProjectNode, target: UUID) -> Set<UUID> {
        func find(_ node: ProjectNode, ancestors: Set<UUID>) -> Set<UUID>? {
            if node.id == target { return ancestors.union([node.id]) }
            for child in node.children { if let found = find(child, ancestors: ancestors.union([node.id])) { return found } }
            return nil
        }
        return find(root, ancestors: []) ?? [root.id]
    }
}
