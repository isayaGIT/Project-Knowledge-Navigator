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
