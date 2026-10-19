import Foundation

struct ProjectNode: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var children: [ProjectNode]
    var content: [NodeContent]

    init(id: UUID = UUID(), title: String, children: [ProjectNode] = [], content: [NodeContent] = []) {
        self.id = id; self.title = title; self.children = children; self.content = content
    }
    var images: [NodeContent] { content.filter { $0.kind == .image } }
    func node(id target: UUID) -> ProjectNode? {
        if id == target { return self }
        for child in children { if let found = child.node(id: target) { return found } }
        return nil
    }
    @discardableResult mutating func updateNode(id target: UUID, _ update: (inout ProjectNode) -> Void) -> Bool {
        if id == target { update(&self); return true }
        for index in children.indices { if children[index].updateNode(id: target, update) { return true } }
        return false
    }
}

struct NodeContent: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case markdown, image, audio, video, link }
    var id: UUID
    var kind: Kind
    var title: String
    /// Relative to the project data directory where possible.
    var path: String
    init(id: UUID = UUID(), kind: Kind, title: String, path: String) {
        self.id = id; self.kind = kind; self.title = title; self.path = path
    }
}

struct ProjectManifest: Codable, Equatable {
    var schemaVersion: Int = 1
    var projectID: UUID
    var name: String
    var root: ProjectNode
    var selectedNodeID: UUID?

    static func sample() -> ProjectManifest {
        let furniture = ProjectNode(title: "Furniture Design", content: (1...12).map {
            NodeContent(kind: .image, title: "Reference \($0)", path: "Media/furniture-\($0).jpg")
        })
        let design = ProjectNode(title: "Design", children: [
            ProjectNode(title: "Furniture", children: [furniture]),
            ProjectNode(title: "Lighting Design", content: [NodeContent(kind: .markdown, title: "Lighting Principles", path: "Documents/lighting-principles.md")])
        ])
        let rooms = ProjectNode(title: "Rooms", children: [design, ProjectNode(title: "Bathroom")])
        let root = ProjectNode(title: "ZPing", children: [rooms, ProjectNode(title: "Character"), ProjectNode(title: "Interaction")])
        return ProjectManifest(projectID: UUID(), name: "ZPing", root: root, selectedNodeID: furniture.id)
    }
}
