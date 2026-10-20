import XCTest
@testable import ProjectKnowledgeNavigator

final class ProjectNodeTests: XCTestCase {
    func testUnlimitedNestingAndLookup() {
        let leaf = ProjectNode(title: "Leaf")
        var root = leaf
        for level in (0..<120).reversed() { root = ProjectNode(title: "Level \(level)", children: [root]) }
        XCTAssertEqual(root.node(id: leaf.id)?.title, "Leaf")
    }

    func testNodeCanContainChildrenAndManyImages() throws {
        let images = (0..<250).map { NodeContent(kind: .image, title: "Image \($0)", path: "Media/\($0).jpg") }
        let node = ProjectNode(title: "Mixed", children: [ProjectNode(title: "Nested")], content: images)
        XCTAssertEqual(node.children.count, 1); XCTAssertEqual(node.images.count, 250)
        XCTAssertEqual(try JSONDecoder().decode(ProjectNode.self, from: JSONEncoder().encode(node)), node)
    }

    func testNodeContentSupportsAnnotationsAndArbitraryFiles() throws {
        let image = NodeContent(kind: .image, title: "Reference", path: "Media/reference.png", annotation: "Warm indirect light")
        let file = NodeContent(kind: .file, title: "CAD model", path: "Media/chair.step")
        let document = NodeContent(kind: .markdown, title: "Principles", path: "Documents/principles.md")
        let node = ProjectNode(title: "Furniture", content: [image, file, document])
        let decoded = try JSONDecoder().decode(ProjectNode.self, from: JSONEncoder().encode(node))
        XCTAssertEqual(decoded.content[0].annotation, "Warm indirect light")
        XCTAssertEqual(decoded.content.map(\.kind), [.image, .file, .markdown])
    }

    func testLegacyContentWithoutAnnotationStillDecodes() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","kind":"image","title":"Old image","path":"Media/old.png"}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(NodeContent.self, from: json)
        XCTAssertNil(item.annotation)
    }


    func testFilmstripVisibleFramesFitWithoutClippingTheLastFrame() {
        XCTAssertEqual(FilmstripMetrics.visibleCount(width: 510, frameWidth: 54, gap: 3, itemCount: 11), 9)
        XCTAssertEqual(FilmstripMetrics.visibleCount(width: 566, frameWidth: 54, gap: 3, itemCount: 100), 9)
        XCTAssertEqual(FilmstripMetrics.visibleCount(width: 567, frameWidth: 54, gap: 3, itemCount: 100), 10)
        XCTAssertEqual(FilmstripMetrics.visibleCount(width: 510, frameWidth: 54, gap: 3, itemCount: 4), 4)
    }

    func testFilmstripPixelScrollIsContinuousAcrossFrameBoundaries() {
        let width: CGFloat = 510
        let frameWidth: CGFloat = 54
        let gap: CGFloat = 3
        let count = 11
        let maxOffset = FilmstripMetrics.maxScrollOffset(width: width, itemCount: count, frameWidth: frameWidth, gap: gap)
        XCTAssertEqual(maxOffset, 114, accuracy: 0.001)
        XCTAssertEqual(FilmstripMetrics.scrollOffset(progress: 0, width: width, itemCount: count, frameWidth: frameWidth, gap: gap), 0, accuracy: 0.001)
        XCTAssertEqual(FilmstripMetrics.scrollOffset(progress: 0.5, width: width, itemCount: count, frameWidth: frameWidth, gap: gap), 57, accuracy: 0.001)
        XCTAssertEqual(FilmstripMetrics.scrollOffset(progress: 1, width: width, itemCount: count, frameWidth: frameWidth, gap: gap), 114, accuracy: 0.001)

        // Splitting pixel offset into whole frames + fractional translation must reconstruct the same offset.
        for offset: CGFloat in [0, 0.5, 28.5, 56.9, 57, 57.1, 85.5, 113.9, 114] {
            let first = FilmstripMetrics.firstVisibleIndex(scrollOffset: offset, frameWidth: frameWidth, gap: gap, itemCount: count)
            let partial = FilmstripMetrics.partialFrameOffset(scrollOffset: offset, frameWidth: frameWidth, gap: gap)
            XCTAssertEqual(CGFloat(first) * (frameWidth + gap) + partial, offset, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(partial, 0)
            XCTAssertLessThan(partial, frameWidth + gap)
        }
    }

    func testFilmstripDraggingSelectsAllImagesInOrder() {
        let width: CGFloat = 510
        let frameWidth: CGFloat = 54
        let gap: CGFloat = 3
        let count = 11
        let samples: [CGFloat] = stride(from: CGFloat(0), through: width, by: 10).map { $0 } + [width]
        let indices = samples.map { x -> Int in
            let progress = min(max(x / width, 0), 1)
            let offset = FilmstripMetrics.scrollOffset(progress: progress, width: width, itemCount: count, frameWidth: frameWidth, gap: gap)
            return FilmstripMetrics.selectedIndex(contentX: x + offset, itemCount: count, frameWidth: frameWidth, gap: gap)
        }
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, 10)
        XCTAssertEqual(indices, indices.sorted(), "Dragging from left to right must not move selection backwards")
        XCTAssertEqual(Set(indices), Set(0...10), "A continuous drag must cross every image, not skip frames")
    }

}

@MainActor
final class ProjectStoreTests: XCTestCase {
    func testDocumentsAndImportedFilesPersistInsideProject() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let nodeID = store.manifest.root.id
        store.addDocument(to: nodeID)
        let document = try XCTUnwrap(store.manifest.root.content.first)
        store.updateDocument(nodeID: nodeID, itemID: document.id, title: "Principles", body: "# Principles\n\nWarm light.")
        XCTAssertEqual(store.documentBody(for: document), "# Principles\n\nWarm light.")

        let source = directory.appendingPathComponent("chair.step")
        try "CAD placeholder".write(to: source, atomically: true, encoding: .utf8)
        store.importItems([source], to: nodeID)
        let imported = try XCTUnwrap(store.manifest.root.content.first(where: { $0.title == "chair" }))
        XCTAssertEqual(imported.kind, .file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaURL(for: imported).path))
        XCTAssertTrue(imported.path.contains(store.manifest.projectID.uuidString))
    }

    func testSavingLegacyDocumentCreatesMissingParentDirectoryWithoutCrashing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let node = try XCTUnwrap(store.manifest.root.children.first?.children.first?.children.first(where: { $0.title == "Lighting Design" }))
        let item = try XCTUnwrap(node.content.first(where: { $0.kind == .markdown }))

        store.updateDocument(nodeID: node.id, itemID: item.id, title: item.title, body: "# Lighting\n\nSaved safely.")

        XCTAssertEqual(store.documentBody(for: item), "# Lighting\n\nSaved safely.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaURL(for: item).path))
    }

    func testProjectsAndNodeStatePersistAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        store.createProject(named: "Research")
        let rootID = store.manifest.root.id
        store.addChild(to: rootID)
        let projectID = store.selectedProjectID
        let restored = ProjectStore(rootDirectory: directory)
        XCTAssertEqual(restored.selectedProjectID, projectID)
        XCTAssertEqual(restored.manifest.name, "Research")
        XCTAssertEqual(restored.manifest.root.children.first?.title, "New Node")
        XCTAssertTrue(restored.projects.contains(where: { $0.name == "ZPing" }))
    }

    func testAddSiblingInsertsImmediatelyAfterSelectedNode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let rootID = store.manifest.root.id
        let siblings = store.manifest.root.children
        let target = try XCTUnwrap(siblings.first(where: { $0.title == "Character" }))

        let createdID = store.addSibling(after: target.id)

        XCTAssertEqual(store.manifest.root.children.map(\.id), [siblings[0].id, target.id, createdID, siblings[2].id])
        XCTAssertEqual(store.selectedNodeID, createdID)
        XCTAssertTrue(store.expandedNodeIDs.contains(rootID))
    }

    func testAddSiblingAtNestedDepthPreservesItsParent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let rooms = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Rooms" }))
        let design = try XCTUnwrap(rooms.children.first(where: { $0.title == "Design" }))
        let target = try XCTUnwrap(design.children.first(where: { $0.title == "Furniture" }))

        let createdID = store.addSibling(after: target.id)

        let updatedDesign = try XCTUnwrap(store.manifest.root.node(id: design.id))
        XCTAssertEqual(updatedDesign.children.map(\.id), [target.id, createdID, design.children[1].id])
        XCTAssertEqual(store.manifest.root.node(id: createdID)?.title, "")
    }

    func testAddSiblingWhenProjectRootIsSelectedAppendsTopLevelChild() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let rootID = store.manifest.root.id
        let previousIDs = store.manifest.root.children.map(\.id)

        let createdID = store.addSibling(after: rootID)

        XCTAssertEqual(Array(store.manifest.root.children.dropLast()).map(\.id), previousIDs)
        XCTAssertEqual(store.manifest.root.children.last?.id, createdID)
    }

    func testAddSiblingWithoutSelectionAppendsTopLevelNode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let previousIDs = store.manifest.root.children.map(\.id)

        let createdID = store.addSibling(after: nil)

        XCTAssertEqual(Array(store.manifest.root.children.dropLast()).map(\.id), previousIDs)
        XCTAssertEqual(store.manifest.root.children.last?.id, createdID)
        XCTAssertEqual(store.selectedNodeID, createdID)
    }

    func testDeleteNodesRemovesWholeSubtreeAndDeduplicatesSelectedDescendants() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let rootID = store.manifest.root.id
        let rooms = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Rooms" }))
        let furniture = try XCTUnwrap(store.manifest.root.node(id: rooms.id)?.children.first?.children.first)
        let deleted = store.deleteNodes(ids: [rooms.id, furniture.id])

        XCTAssertEqual(deleted, 6)
        XCTAssertNil(store.manifest.root.node(id: rooms.id))
        XCTAssertNotNil(store.manifest.root.node(id: rootID))
        XCTAssertEqual(store.manifest.root.children.map(\.title), ["Character", "Interaction"])
        XCTAssertEqual(store.selectedNodeID, rootID)
    }

    func testTreeUndoAndRedoRestoreNodeRename() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let original = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Character" }))

        store.rename(original, to: "Residents")
        XCTAssertEqual(store.manifest.root.node(id: original.id)?.title, "Residents")
        XCTAssertTrue(store.canUndoTreeChange)

        store.undoTreeChange()
        XCTAssertEqual(store.manifest.root.node(id: original.id)?.title, "Character")
        XCTAssertTrue(store.canRedoTreeChange)

        store.redoTreeChange()
        XCTAssertEqual(store.manifest.root.node(id: original.id)?.title, "Residents")
        XCTAssertTrue(store.canUndoTreeChange)
    }

    func testCancellingBlankSiblingDoesNotCreateAnUndoEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let previous = try XCTUnwrap(store.manifest.root.children.first)

        let createdID = store.addSibling(after: previous.id)
        XCTAssertNotNil(store.manifest.root.node(id: createdID))
        XCTAssertFalse(store.canUndoTreeChange, "An unfinished blank node is provisional, not a committed undoable action")

        XCTAssertEqual(store.deleteNodes(ids: [createdID]), 1)
        store.flushPendingPersistence()
        XCTAssertNil(store.manifest.root.node(id: createdID))
        XCTAssertFalse(store.canUndoTreeChange, "Cancelling a blank node must not create a spurious undo action")
    }

    func testUndoAndRedoDeletionRestoreLocalContentFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        store.addChild(to: store.manifest.root.id)
        let nodeID = try XCTUnwrap(store.selectedNodeID)
        store.addDocument(to: nodeID)
        let node = try XCTUnwrap(store.manifest.root.node(id: nodeID))
        let item = try XCTUnwrap(node.content.first)
        let fileURL = store.mediaURL(for: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        XCTAssertEqual(store.deleteNodes(ids: [nodeID]), 1)
        store.flushPendingPersistence()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        store.undoTreeChange()
        store.flushPendingPersistence()
        XCTAssertNotNil(store.manifest.root.node(id: nodeID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Undo must restore the deleted node's owned files")

        store.redoTreeChange()
        store.flushPendingPersistence()
        XCTAssertNil(store.manifest.root.node(id: nodeID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Redo must reapply file cleanup")
    }

    func testBatchIndentIsOneUndoAction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let originalIDs = store.manifest.root.children.map(\.id)
        let character = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Character" }))
        let interaction = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Interaction" }))

        XCTAssertTrue(store.indentNodes(ids: [character.id, interaction.id]))
        XCTAssertEqual(store.manifest.root.children.count, 1)

        store.undoTreeChange()
        XCTAssertEqual(store.manifest.root.children.map(\.id), originalIDs)
    }

    func testUndoHistoryIsBoundedToOneHundredOperations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let rootID = store.manifest.root.id

        for _ in 0..<101 { store.addChild(to: rootID) }
        XCTAssertEqual(store.manifest.root.children.count, 104)
        for _ in 0..<100 { store.undoTreeChange() }
        XCTAssertEqual(store.manifest.root.children.count, 4, "Only the latest 100 tree operations should remain undoable")
        XCTAssertFalse(store.canUndoTreeChange)
        XCTAssertTrue(store.canRedoTreeChange)
    }

    func testDeleteSelectsPreviousVisibleNodeAndRedoPreservesSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let rooms = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Rooms" }))
        let previousVisible = try XCTUnwrap(rooms.children.first(where: { $0.title == "Bathroom" }))
        let deleted = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Character" }))

        XCTAssertEqual(store.deleteNodes(ids: [deleted.id], selecting: previousVisible.id), 1)
        XCTAssertEqual(store.selectedNodeID, previousVisible.id)

        store.undoTreeChange()
        XCTAssertNotNil(store.manifest.root.node(id: deleted.id))

        store.redoTreeChange()
        XCTAssertNil(store.manifest.root.node(id: deleted.id))
        XCTAssertEqual(store.selectedNodeID, previousVisible.id)
    }

    func testDeleteNodesNeverDeletesProjectRoot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let rootID = store.manifest.root.id
        let originalChildren = store.manifest.root.children.map(\.id)

        XCTAssertEqual(store.deleteNodes(ids: [rootID]), 0)
        XCTAssertEqual(store.manifest.root.children.map(\.id), originalChildren)
    }

    func testSelectedNodePersistsAsynchronouslyAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let target = try XCTUnwrap(store.manifest.root.children.first(where: { $0.title == "Rooms" }))

        store.select(target)
        store.flushPendingPersistence()

        let restored = ProjectStore(rootDirectory: directory)
        XCTAssertEqual(restored.selectedNodeID, target.id)
        XCTAssertEqual(restored.manifest.selectedNodeID, target.id)
    }

    func testRapidNodeMovesPersistTheLatestTreeOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let root = store.manifest.root
        let rooms = try XCTUnwrap(root.children.first(where: { $0.title == "Rooms" }))
        let character = try XCTUnwrap(root.children.first(where: { $0.title == "Character" }))
        let interaction = try XCTUnwrap(root.children.first(where: { $0.title == "Interaction" }))

        XCTAssertTrue(store.moveNode(id: character.id, to: rooms.id, placement: .inside))
        XCTAssertTrue(store.moveNode(id: interaction.id, to: rooms.id, placement: .before))
        store.flushPendingPersistence()

        let restored = ProjectStore(rootDirectory: directory)
        XCTAssertEqual(restored.manifest.root.children.map(\.title), ["Interaction", "Rooms"])
        XCTAssertEqual(restored.manifest.root.node(id: rooms.id)?.children.last?.id, character.id)
    }

    func testNodeReorganizationPersistsAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectStore(rootDirectory: directory)
        let root = store.manifest.root
        let rooms = try XCTUnwrap(root.children.first(where: { $0.title == "Rooms" }))
        let character = try XCTUnwrap(root.children.first(where: { $0.title == "Character" }))

        store.selectedNodeID = character.id
        XCTAssertTrue(store.moveNode(id: character.id, to: rooms.id, placement: .inside))
        store.flushPendingPersistence()
        let restored = ProjectStore(rootDirectory: directory)
        XCTAssertEqual(restored.manifest.root.node(id: rooms.id)?.children.last?.id, character.id)
        XCTAssertEqual(restored.selectedNodeID, character.id)
        XCTAssertTrue(restored.expandedNodeIDs.contains(rooms.id))
    }
}

final class ProjectNodeMovementTests: XCTestCase {
    private func makeTree() -> ProjectNode {
        ProjectNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Root", children: [
            ProjectNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, title: "A", children: [
                ProjectNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, title: "A1"),
                ProjectNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, title: "A2")
            ]),
            ProjectNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!, title: "B"),
            ProjectNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!, title: "C")
        ])
    }

    func testDropInsideMovesWholeSubtreeAndPreservesIdentityAndContent() throws {
        var tree = makeTree()
        let movingID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let note = NodeContent(kind: .markdown, title: "Keep", path: "Documents/keep.md")
        tree.updateNode(id: movingID) { $0.content = [note] }

        XCTAssertTrue(tree.moveNode(id: movingID, to: targetID, placement: .inside))
        let moved = try XCTUnwrap(tree.node(id: movingID))
        XCTAssertEqual(moved.content, [note])
        XCTAssertNotNil(moved.node(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!))
        XCTAssertEqual(tree.node(id: targetID)?.children.map(\.id), [movingID])
        XCTAssertEqual(tree.children.map(\.title), ["B", "C"])
    }

    func testDropBeforeAndAfterPreserveSiblingOrder() throws {
        var tree = makeTree()
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let c = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

        XCTAssertTrue(tree.moveNode(id: c, to: b, placement: .before))
        XCTAssertEqual(tree.children.map(\.title), ["A", "C", "B"])
        XCTAssertTrue(tree.moveNode(id: b, to: a, placement: .after))
        XCTAssertEqual(tree.children.map(\.title), ["A", "B", "C"])
    }

    func testIndentAndOutdentChangeOneLevel() throws {
        var tree = makeTree()
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

        XCTAssertTrue(tree.indentNode(id: b))
        XCTAssertEqual(tree.node(id: a)?.children.map(\.id), [UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, b])
        XCTAssertTrue(tree.outdentNode(id: b))
        XCTAssertEqual(tree.children.map(\.id), [a, b, UUID(uuidString: "00000000-0000-0000-0000-000000000030")!])
    }

    func testContentBearingNodeCanBeIndentedIntoAnotherContentBearingNode() throws {
        var tree = makeTree()
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let parentNote = NodeContent(kind: .markdown, title: "Parent note", path: "Documents/parent.md")
        let childNote = NodeContent(kind: .markdown, title: "Child note", path: "Documents/child.md")
        tree.updateNode(id: a) { $0.content = [parentNote] }
        tree.updateNode(id: b) { $0.content = [childNote] }

        XCTAssertTrue(tree.indentNode(id: b))
        let parent = try XCTUnwrap(tree.node(id: a))
        let child = try XCTUnwrap(parent.node(id: b))
        XCTAssertEqual(parent.content, [parentNote])
        XCTAssertEqual(child.content, [childNote])
        XCTAssertEqual(parent.children.last?.id, b)
    }

    func testRejectRootMovesCyclesAndInvalidSiblingTarget() {
        var tree = makeTree()
        let root = tree.id
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let a1 = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let original = tree

        XCTAssertFalse(tree.moveNode(id: root, to: a, placement: .inside))
        XCTAssertFalse(tree.moveNode(id: a, to: a1, placement: .inside))
        XCTAssertFalse(tree.moveNode(id: a, to: root, placement: .before))
        XCTAssertFalse(tree.indentNode(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!))
        XCTAssertFalse(tree.outdentNode(id: a))
        XCTAssertEqual(tree, original)
    }

    func testMoveRelativeToNestedTargetUpdatesCorrectParent() {
        var tree = makeTree()
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let a2 = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

        XCTAssertTrue(tree.moveNode(id: b, to: a2, placement: .after))
        XCTAssertEqual(tree.children.map(\.title), ["A", "C"])
        XCTAssertEqual(tree.node(id: a)?.children.map(\.id), [UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, a2, b])
    }

    func testMoveRelativeToDescendantIsRejectedWithoutMutation() {
        var tree = makeTree()
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let a1 = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let original = tree
        XCTAssertFalse(tree.moveNode(id: a, to: a1, placement: .after))
        XCTAssertEqual(tree, original)
    }
}
