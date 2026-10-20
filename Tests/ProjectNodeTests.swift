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

    func testFilmstripScrollRangeAndSelectionStayAlignedAcrossTheViewport() {
        let width: CGFloat = 510
        let visible = FilmstripMetrics.visibleCount(width: width, frameWidth: 54, gap: 3, itemCount: 11)
        XCTAssertEqual(visible, 9)
        XCTAssertEqual(FilmstripMetrics.scrollOffset(progress: 0, itemCount: 11, visibleCount: visible), 0)
        XCTAssertEqual(FilmstripMetrics.scrollOffset(progress: 0.5, itemCount: 11, visibleCount: visible), 1)
        XCTAssertEqual(FilmstripMetrics.scrollOffset(progress: 1, itemCount: 11, visibleCount: visible), 2)

        XCTAssertEqual(FilmstripMetrics.selectedIndex(x: 0, width: width, itemCount: 11, visibleCount: visible, frameWidth: 54, gap: 3), 0)
        XCTAssertEqual(FilmstripMetrics.selectedIndex(x: width, width: width, itemCount: 11, visibleCount: visible, frameWidth: 54, gap: 3), 10)

        let samples: [CGFloat] = [0, 50, 100, 150, 200, 250, 300, 350, 400, 450, 510]
        let indices = samples.map {
            FilmstripMetrics.selectedIndex(x: $0, width: width, itemCount: 11, visibleCount: visible, frameWidth: 54, gap: 3)
        }
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, 10)
        XCTAssertEqual(indices, indices.sorted(), "Dragging from left to right must not move selection backwards")
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
}
