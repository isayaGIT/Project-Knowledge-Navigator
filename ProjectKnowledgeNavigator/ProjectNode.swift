import Foundation

enum NodeMovePlacement: Equatable {
    case before
    case inside
    case after
}

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

    func parentID(of target: UUID) -> UUID? {
        for child in children {
            if child.id == target { return id }
            if let found = child.parentID(of: target) { return found }
        }
        return nil
    }

    /// Moves a complete subtree. Invalid moves leave the original tree unchanged.
    @discardableResult mutating func moveNode(id movingID: UUID, to targetID: UUID, placement: NodeMovePlacement) -> Bool {
        guard movingID != id,
              movingID != targetID,
              let moving = node(id: movingID),
              node(id: targetID) != nil,
              moving.node(id: targetID) == nil else { return false }
        if placement != .inside && targetID == id { return false }

        var updated = self
        guard let extracted = updated.removeNode(id: movingID) else { return false }
        let inserted: Bool
        switch placement {
        case .inside:
            inserted = updated.updateNode(id: targetID) { $0.children.append(extracted) }
        case .before:
            inserted = updated.insertNode(extracted, relativeTo: targetID, after: false)
        case .after:
            inserted = updated.insertNode(extracted, relativeTo: targetID, after: true)
        }
        guard inserted else { return false }
        self = updated
        return true
    }

    /// Indents one level by making the node a child of its previous sibling.
    @discardableResult mutating func indentNode(id target: UUID) -> Bool {
        guard let parent = parentID(of: target),
              let siblings = node(id: parent)?.children,
              let index = siblings.firstIndex(where: { $0.id == target }),
              index > 0 else { return false }
        return moveNode(id: target, to: siblings[index - 1].id, placement: .inside)
    }

    /// Outdents one level by placing the node immediately after its parent.
    @discardableResult mutating func outdentNode(id target: UUID) -> Bool {
        guard let parent = parentID(of: target),
              parentID(of: parent) != nil else { return false }
        return moveNode(id: target, to: parent, placement: .after)
    }

    private mutating func removeNode(id target: UUID) -> ProjectNode? {
        for index in children.indices {
            if children[index].id == target { return children.remove(at: index) }
            if let removed = children[index].removeNode(id: target) { return removed }
        }
        return nil
    }

    private mutating func insertNode(_ node: ProjectNode, relativeTo target: UUID, after: Bool) -> Bool {
        for index in children.indices {
            if children[index].id == target {
                children.insert(node, at: index + (after ? 1 : 0))
                return true
            }
            if children[index].insertNode(node, relativeTo: target, after: after) { return true }
        }
        return false
    }
}

struct NodeContent: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case markdown, image, audio, video, link, file }
    var id: UUID
    var kind: Kind
    var title: String
    /// Relative to the local app data directory where possible.
    var path: String
    /// User-authored image notes, source context, or other item-specific annotation.
    var annotation: String?
    init(id: UUID = UUID(), kind: Kind, title: String, path: String, annotation: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.path = path; self.annotation = annotation
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
