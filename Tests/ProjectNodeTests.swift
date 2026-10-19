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

    func testFilmstripWindowNeverAddsLeadingOrTrailingPadding() {
        func offset(width: Double, frameWidth: Double, gap: Double, count: Int, selected: Int) -> Double {
            let step = frameWidth + gap
            let visible = max(1, Int(ceil(width / step)) + 2)
            let start = max(0, min(max(0, count - visible), selected - visible / 2))
            let total = Double(count) * frameWidth + Double(max(0, count - 1)) * gap
            return total <= width ? 0 : -Double(start) * step
        }
        XCTAssertEqual(offset(width: 300, frameWidth: 54, gap: 3, count: 2, selected: 0), 0)
        XCTAssertEqual(offset(width: 200, frameWidth: 54, gap: 3, count: 100, selected: 0), 0)
        XCTAssertLessThan(offset(width: 200, frameWidth: 54, gap: 3, count: 100, selected: 99), 0)
    }

    func testPointerPositionMapsAcrossWholeFilmstrip() {
        func index(x: Double, width: Double, count: Int) -> Int {
            guard count > 1, width > 0 else { return 0 }
            return Int((min(max(x / width, 0), 1) * Double(count - 1)).rounded())
        }
        XCTAssertEqual(index(x: 0, width: 100, count: 12), 0)
        XCTAssertEqual(index(x: 50, width: 100, count: 12), 6)
        XCTAssertEqual(index(x: 100, width: 100, count: 12), 11)
        XCTAssertEqual(index(x: 200, width: 100, count: 12), 11)
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
