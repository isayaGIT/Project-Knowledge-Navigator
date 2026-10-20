import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

struct ProjectSummary: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
}

private struct ProjectCatalog: Codable {
    var projects: [ProjectSummary]
    var selectedProjectID: UUID
}

private struct ProjectTreeUndoSnapshot: Equatable {
    var manifest: ProjectManifest
    var projects: [ProjectSummary]
    var selectedProjectID: UUID
    var selectedNodeID: UUID?
    var expandedNodeIDs: Set<UUID>
}

private struct UndoFileBackup {
    var sourceURL: URL
    var backupURL: URL
}

private struct ProjectTreeUndoRecord {
    var before: ProjectTreeUndoSnapshot
    var after: ProjectTreeUndoSnapshot
    var fileBackups: [UndoFileBackup]
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var manifest: ProjectManifest
    @Published private(set) var projects: [ProjectSummary]
    @Published private(set) var selectedProjectID: UUID
    @Published var selectedNodeID: UUID?
    @Published var expandedNodeIDs: Set<UUID>
    @Published private(set) var canUndoTreeChange = false
    @Published private(set) var canRedoTreeChange = false

    private let rootDirectory: URL
    private let catalogURL: URL
    private let syncWidgetDefaults: Bool
    private let undoCacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProjectKnowledgeNavigator-Undo-\(UUID().uuidString)", isDirectory: true)
    private static let maximumTreeUndoLevels = 100
    private var treeUndoStack: [ProjectTreeUndoRecord] = []
    private var treeRedoStack: [ProjectTreeUndoRecord] = []
    private var pendingNodeCreationSnapshots: [UUID: ProjectTreeUndoSnapshot] = [:]
    /// Disk writes triggered by a tree drop must never block AppKit's drag-end event.
    /// A serial queue preserves manifest/catalog write order across rapid consecutive moves.
    private let persistenceQueue = DispatchQueue(label: "com.isayaGIT.ProjectKnowledgeNavigator.persistence", qos: .utility)
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
        syncWidgetSummary()
    }

    deinit {
        let queue = persistenceQueue
        let cacheDirectory = undoCacheDirectory
        queue.sync {}
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    func select(_ node: ProjectNode) {
        guard selectedNodeID != node.id || manifest.selectedNodeID != node.id else { return }
        selectedNodeID = node.id
        manifest.selectedNodeID = node.id
        saveSelectedNodeAsynchronously()
    }

    /// Selection is frequent, lightweight UI state. Persist only its manifest snapshot
    /// on the serial queue; never block a mouse-up on catalog writes or WidgetKit IPC.
    private func saveSelectedNodeAsynchronously() {
        var snapshot = manifest
        snapshot.selectedNodeID = selectedNodeID
        let url = manifestURL(for: snapshot.projectID)
        let directory = projectsDirectory
        persistenceQueue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(snapshot).write(to: url, options: .atomic)
            } catch {
                NSLog("Project Knowledge Navigator: could not persist node selection: %@", error.localizedDescription)
            }
        }
    }

    func toggleExpanded(_ node: ProjectNode) {
        if expandedNodeIDs.contains(node.id) { expandedNodeIDs.remove(node.id) }
        else { expandedNodeIDs.insert(node.id) }
    }

    func createProject(named rawName: String) {
        flushPendingPersistence()
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        clearTreeUndoHistory()
        persistCurrent()
        let root = ProjectNode(title: name)
        let next = ProjectManifest(projectID: UUID(), name: name, root: root, selectedNodeID: root.id)
        projects.append(ProjectSummary(id: next.projectID, name: name))
        selectedProjectID = next.projectID
        manifest = next
        selectedNodeID = root.id
        expandedNodeIDs = [root.id]
        persistCurrent(); persistCatalog(); syncWidgetSummary()
    }

    func selectProject(_ id: UUID) {
        flushPendingPersistence()
        guard id != selectedProjectID,
              let summary = projects.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: manifestURL(for: summary.id)),
              let next = try? JSONDecoder().decode(ProjectManifest.self, from: data) else { return }
        clearTreeUndoHistory()
        persistCurrent()
        selectedProjectID = id
        manifest = next
        selectedNodeID = next.selectedNodeID ?? next.root.id
        expandedNodeIDs = Self.ancestorIDs(in: next.root, target: selectedNodeID ?? next.root.id)
        persistCatalog()
        syncWidgetSummary()
    }

    func open(projectID: UUID, nodeID: UUID) {
        if projectID != selectedProjectID { selectProject(projectID) }
        guard let target = manifest.root.node(id: nodeID) else { return }
        selectedNodeID = target.id
        expandedNodeIDs = Self.ancestorIDs(in: manifest.root, target: target.id)
        save()
    }

    func addChild(to parentID: UUID?) {
        let before = makeTreeUndoSnapshot()
        let parent = parentID ?? manifest.root.id
        let child = ProjectNode(title: "New Node")
        _ = manifest.root.updateNode(id: parent) { $0.children.append(child) }
        expandedNodeIDs.insert(parent)
        selectedNodeID = child.id
        recordTreeUndo(before: before)
        save()
    }

    /// Inserts a new node immediately after the selected node. With no selection, or
    /// when the project root itself is selected, appends a top-level child.
    @discardableResult func addSibling(after nodeID: UUID?) -> UUID {
        let before = makeTreeUndoSnapshot()
        let newNode = ProjectNode(title: "")
        if let nodeID, nodeID != manifest.root.id,
           let parentID = manifest.root.parentID(of: nodeID) {
            _ = manifest.root.updateNode(id: parentID) { parent in
                guard let index = parent.children.firstIndex(where: { $0.id == nodeID }) else { return }
                parent.children.insert(newNode, at: index + 1)
            }
            expandedNodeIDs.insert(parentID)
        } else {
            manifest.root.children.append(newNode)
            expandedNodeIDs.insert(manifest.root.id)
        }
        selectedNodeID = newNode.id
        pendingNodeCreationSnapshots[newNode.id] = before
        save()
        return newNode.id
    }

    /// Deletes selected node subtrees in one tree pass. Disk cleanup and persistence run off the UI thread.
    @discardableResult func deleteNodes(ids: [UUID], selecting preferredSelectionID: UUID? = nil) -> Int {
        let requested = Set(ids).subtracting([manifest.root.id])
        guard !requested.isEmpty else { return 0 }
        let cancelledProvisionalCreation = requested.count == 1
            && requested.first.map { pendingNodeCreationSnapshots[$0] != nil } == true
        let undoBefore = cancelledProvisionalCreation
            ? requested.first.flatMap { pendingNodeCreationSnapshots[$0] } ?? makeTreeUndoSnapshot()
            : makeTreeUndoSnapshot()

        var deletedCount = 0
        var removedContent: [NodeContent] = []

        func collect(_ node: ProjectNode) {
            deletedCount += 1
            removedContent.append(contentsOf: node.content)
            node.children.forEach(collect)
        }

        func removeRequestedSubtrees(from node: inout ProjectNode) {
            var keptChildren: [ProjectNode] = []
            keptChildren.reserveCapacity(node.children.count)
            for var child in node.children {
                if requested.contains(child.id) {
                    collect(child)
                } else {
                    removeRequestedSubtrees(from: &child)
                    keptChildren.append(child)
                }
            }
            node.children = keptChildren
        }

        var updatedRoot = manifest.root
        removeRequestedSubtrees(from: &updatedRoot)
        guard deletedCount > 0 else { return 0 }

        manifest.root = updatedRoot
        let selectionAfterDeletion = preferredSelectionID.flatMap { updatedRoot.node(id: $0)?.id } ?? updatedRoot.id
        selectedNodeID = selectionAfterDeletion
        manifest.selectedNodeID = selectionAfterDeletion
        expandedNodeIDs.insert(manifest.root.id)
        for id in requested { pendingNodeCreationSnapshots.removeValue(forKey: id) }

        let remainingPaths = contentFilePaths(in: updatedRoot)
        let removedURLs = removedContent
            .filter { !$0.path.hasPrefix("http://") && !$0.path.hasPrefix("https://") }
            .map { mediaURL(for: $0).standardizedFileURL }
        let uniqueRemovedURLs = Dictionary(grouping: removedURLs, by: \.path).compactMap { $0.value.first }
            .filter { !remainingPaths.contains($0.path) }
        let backups = makeUndoBackups(for: uniqueRemovedURLs)
        if !cancelledProvisionalCreation {
            recordTreeUndo(before: undoBefore, fileBackups: backups)
        }
        saveMovedTreeAsynchronously(deletingFiles: backups)
        return deletedCount
    }

    @discardableResult func moveNode(id nodeID: UUID, to targetID: UUID, placement: NodeMovePlacement) -> Bool {
        let before = makeTreeUndoSnapshot()
        var root = manifest.root
        guard root.moveNode(id: nodeID, to: targetID, placement: placement) else { return false }
        manifest.root = root
        if placement == .inside { expandedNodeIDs.insert(targetID) }
        if let newParentID = root.parentID(of: nodeID) { expandedNodeIDs.insert(newParentID) }
        recordTreeUndo(before: before)
        saveMovedTreeAsynchronously()
        return true
    }

    @discardableResult func indentNode(id nodeID: UUID) -> Bool {
        indentNodes(ids: [nodeID])
    }

    @discardableResult func indentNodes(ids: [UUID]) -> Bool {
        let before = makeTreeUndoSnapshot()
        var root = manifest.root
        var changed = false
        for nodeID in ids {
            guard root.indentNode(id: nodeID) else { continue }
            changed = true
            if let parentID = root.parentID(of: nodeID) { expandedNodeIDs.insert(parentID) }
        }
        guard changed else { return false }
        manifest.root = root
        recordTreeUndo(before: before)
        save()
        return true
    }

    @discardableResult func outdentNode(id nodeID: UUID) -> Bool {
        outdentNodes(ids: [nodeID])
    }

    @discardableResult func outdentNodes(ids: [UUID]) -> Bool {
        let before = makeTreeUndoSnapshot()
        var root = manifest.root
        var changed = false
        for nodeID in ids {
            guard root.outdentNode(id: nodeID) else { continue }
            changed = true
            if let parentID = root.parentID(of: nodeID) { expandedNodeIDs.insert(parentID) }
        }
        guard changed else { return false }
        manifest.root = root
        recordTreeUndo(before: before)
        save()
        return true
    }

    func rename(_ node: ProjectNode, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let pendingBefore = pendingNodeCreationSnapshots.removeValue(forKey: node.id)
        let before = pendingBefore ?? makeTreeUndoSnapshot()
        _ = manifest.root.updateNode(id: node.id) { $0.title = title }
        if node.id == manifest.root.id {
            manifest.name = title
            if let index = projects.firstIndex(where: { $0.id == selectedProjectID }) { projects[index].name = title }
        }
        recordTreeUndo(before: before)
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
            let destination = mediaURL(for: item)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try body.write(to: destination, atomically: true, encoding: .utf8)
            _ = manifest.root.updateNode(id: nodeID) { current in
                guard let index = current.content.firstIndex(where: { $0.id == itemID }) else { return }
                if !title.isEmpty { current.content[index].title = title }
            }
            save()
        } catch {
            // Disk or path errors should not terminate the whole app while typing.
            NSLog("Project Knowledge Navigator: could not save document '%@': %@", item.title, error.localizedDescription)
        }
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
        // Current records store paths relative to the app data root; early/sample records
        // stored paths relative to the project's own files directory.
        if item.path.hasPrefix("ProjectFiles/") {
            return rootDirectory.appendingPathComponent(item.path)
        }
        return projectFilesDirectoryURL.appendingPathComponent(item.path)
    }

    func save() {
        flushPendingPersistence()
        manifest.selectedNodeID = selectedNodeID
        persistCurrent(); persistCatalog(); syncWidgetSummary()
    }

    /// Waits for outstanding background tree-move writes before a synchronous save,
    /// project switch, or persistence assertion in tests. It does not wait for UI work.
    func flushPendingPersistence() {
        persistenceQueue.sync {}
    }

    func undoTreeChange() {
        flushPendingPersistence()
        guard let record = treeUndoStack.popLast() else { updateUndoAvailability(); return }
        treeRedoStack.append(record)
        applyTreeUndoSnapshot(record.before, reconciling: record.fileBackups)
        updateUndoAvailability()
    }

    func redoTreeChange() {
        flushPendingPersistence()
        guard let record = treeRedoStack.popLast() else { updateUndoAvailability(); return }
        treeUndoStack.append(record)
        if treeUndoStack.count > Self.maximumTreeUndoLevels {
            discardUndoRecord(treeUndoStack.removeFirst())
        }
        applyTreeUndoSnapshot(record.after, reconciling: record.fileBackups)
        updateUndoAvailability()
    }

    private func makeTreeUndoSnapshot() -> ProjectTreeUndoSnapshot {
        var snapshot = manifest
        snapshot.selectedNodeID = selectedNodeID
        return ProjectTreeUndoSnapshot(
            manifest: snapshot,
            projects: projects,
            selectedProjectID: selectedProjectID,
            selectedNodeID: selectedNodeID,
            expandedNodeIDs: expandedNodeIDs
        )
    }

    private func recordTreeUndo(
        before: ProjectTreeUndoSnapshot,
        fileBackups: [UndoFileBackup] = []
    ) {
        let after = makeTreeUndoSnapshot()
        guard before != after else {
            fileBackups.forEach { purgeUndoBackup($0.backupURL) }
            return
        }
        treeRedoStack.forEach(discardUndoRecord)
        treeRedoStack.removeAll()
        treeUndoStack.append(ProjectTreeUndoRecord(before: before, after: after, fileBackups: fileBackups))
        if treeUndoStack.count > Self.maximumTreeUndoLevels {
            discardUndoRecord(treeUndoStack.removeFirst())
        }
        updateUndoAvailability()
    }

    private func applyTreeUndoSnapshot(_ snapshot: ProjectTreeUndoSnapshot, reconciling backups: [UndoFileBackup]) {
        manifest = snapshot.manifest
        projects = snapshot.projects
        selectedProjectID = snapshot.selectedProjectID
        selectedNodeID = snapshot.selectedNodeID
        expandedNodeIDs = snapshot.expandedNodeIDs
        pendingNodeCreationSnapshots.removeAll()
        saveMovedTreeAsynchronously(reconcilingUndoFiles: backups)
    }

    private func updateUndoAvailability() {
        canUndoTreeChange = !treeUndoStack.isEmpty
        canRedoTreeChange = !treeRedoStack.isEmpty
    }

    private func clearTreeUndoHistory() {
        let records = treeUndoStack + treeRedoStack
        treeUndoStack.removeAll()
        treeRedoStack.removeAll()
        pendingNodeCreationSnapshots.removeAll()
        records.forEach(discardUndoRecord)
        updateUndoAvailability()
    }

    private func discardUndoRecord(_ record: ProjectTreeUndoRecord) {
        for backup in record.fileBackups { purgeUndoBackup(backup.backupURL) }
    }

    private func purgeUndoBackup(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        persistenceQueue.async { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeUndoBackups(for urls: [URL]) -> [UndoFileBackup] {
        guard !urls.isEmpty else { return [] }
        let actionDirectory = undoCacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return urls.enumerated().map { index, source in
            UndoFileBackup(
                sourceURL: source.standardizedFileURL,
                backupURL: actionDirectory.appendingPathComponent("\(index)-\(source.lastPathComponent)")
            )
        }
    }

    private func contentFilePaths(in root: ProjectNode) -> Set<String> {
        var result = Set<String>()
        func collect(_ node: ProjectNode) {
            for item in node.content where !item.path.hasPrefix("http://") && !item.path.hasPrefix("https://") {
                result.insert(mediaURL(for: item).standardizedFileURL.path)
            }
            node.children.forEach(collect)
        }
        collect(root)
        return result
    }

    /// Capture immutable value snapshots on the main actor, then encode and write them
    /// off the main thread. Tree mutations must not block interactive UI callbacks on
    /// serialization, disk writes, media cleanup, or WidgetKit timeline reloads.
    private func saveMovedTreeAsynchronously(
        deletingFiles: [UndoFileBackup] = [],
        reconcilingUndoFiles: [UndoFileBackup] = []
    ) {
        var manifestSnapshot = manifest
        manifestSnapshot.selectedNodeID = selectedNodeID
        let catalogSnapshot = ProjectCatalog(projects: projects, selectedProjectID: selectedProjectID)
        let manifestURLSnapshot = manifestURL(for: manifest.projectID)
        let catalogURLSnapshot = catalogURL
        let projectsDirectorySnapshot = projectsDirectory
        let rootDirectorySnapshot = rootDirectory
        let updateWidget = syncWidgetDefaults
        let widgetName = manifestSnapshot.name
        let widgetProjectID = manifestSnapshot.projectID.uuidString
        let widgetNodes = Array(manifestSnapshot.root.children.prefix(3))
        let widgetTitles = widgetNodes.map(\.title)
        let widgetNodeIDs = widgetNodes.map { $0.id.uuidString }
        let referencedContentPaths = contentFilePaths(in: manifestSnapshot.root)

        persistenceQueue.async {
            for backup in deletingFiles {
                guard FileManager.default.fileExists(atPath: backup.sourceURL.path) else { continue }
                do {
                    try FileManager.default.createDirectory(at: backup.backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if !FileManager.default.fileExists(atPath: backup.backupURL.path) {
                        try FileManager.default.copyItem(at: backup.sourceURL, to: backup.backupURL)
                    }
                    if FileManager.default.fileExists(atPath: backup.backupURL.path) {
                        try FileManager.default.removeItem(at: backup.sourceURL)
                    }
                } catch {
                    NSLog("Project Knowledge Navigator: could not back up a deleted file for undo: %@", error.localizedDescription)
                }
            }
            for backup in reconcilingUndoFiles {
                let shouldExist = referencedContentPaths.contains(backup.sourceURL.standardizedFileURL.path)
                if shouldExist {
                    guard !FileManager.default.fileExists(atPath: backup.sourceURL.path),
                          FileManager.default.fileExists(atPath: backup.backupURL.path) else { continue }
                    do {
                        try FileManager.default.createDirectory(at: backup.sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: backup.backupURL, to: backup.sourceURL)
                    } catch {
                        NSLog("Project Knowledge Navigator: could not restore a deleted file during undo: %@", error.localizedDescription)
                    }
                } else {
                    try? FileManager.default.removeItem(at: backup.sourceURL)
                }
            }
            do {
                try FileManager.default.createDirectory(at: projectsDirectorySnapshot, withIntermediateDirectories: true)
                let manifestEncoder = JSONEncoder()
                manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try manifestEncoder.encode(manifestSnapshot).write(to: manifestURLSnapshot, options: .atomic)

                try FileManager.default.createDirectory(at: rootDirectorySnapshot, withIntermediateDirectories: true)
                let catalogEncoder = JSONEncoder()
                catalogEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try catalogEncoder.encode(catalogSnapshot).write(to: catalogURLSnapshot, options: .atomic)

                if updateWidget,
                   let defaults = UserDefaults(suiteName: "group.com.isayaGIT.ProjectKnowledgeNavigator") {
                    defaults.set(widgetName, forKey: "currentProjectName")
                    defaults.set(widgetProjectID, forKey: "currentProjectID")
                    defaults.set(widgetTitles, forKey: "currentProjectNodeTitles")
                    defaults.set(widgetNodeIDs, forKey: "currentProjectNodeIDs")
                    // WidgetKit's IPC/reload request is not part of the drop critical path
                    // or persistence-queue barrier.
                    DispatchQueue.global(qos: .utility).async {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            } catch {
                NSLog("Project Knowledge Navigator: could not persist a tree change: %@", error.localizedDescription)
            }
        }
    }

    private func syncWidgetSummary() {
        guard syncWidgetDefaults, let defaults = UserDefaults(suiteName: "group.com.isayaGIT.ProjectKnowledgeNavigator") else { return }
        let nodes = manifest.root.children.prefix(3).map { $0 }
        defaults.set(manifest.name, forKey: "currentProjectName")
        defaults.set(manifest.projectID.uuidString, forKey: "currentProjectID")
        defaults.set(nodes.map(\.title), forKey: "currentProjectNodeTitles")
        defaults.set(nodes.map { $0.id.uuidString }, forKey: "currentProjectNodeIDs")
        WidgetCenter.shared.reloadAllTimelines()
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
