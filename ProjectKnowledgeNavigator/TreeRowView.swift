import SwiftUI
import CrossProjectComponents

/// Layout values that belong to the Knowledge Navigator's richer row, not to the shared Tree engine.
enum ProjectTreeRowMetrics {
    static let textRowHeight: CGFloat = 32
    static let filmstripRowHeight: CGFloat = 78
    static let iconSize: CGFloat = 14
    static let filmstripSpacing: CGFloat = 3
    static let filmstripHeight: CGFloat = 42
    static let iconLeading: CGFloat = 7
    static let filmstripLeading: CGFloat = 27
    static let rowTrailing: CGFloat = 6

    static func rowHeight(for node: ProjectNode) -> CGFloat {
        node.images.isEmpty ? textRowHeight : filmstripRowHeight
    }

    static func titleLineCenter(hasFilmstrip: Bool) -> CGFloat {
        guard hasFilmstrip else { return textRowHeight / 2 }
        let groupHeight = iconSize + filmstripSpacing + filmstripHeight
        return (filmstripRowHeight - groupHeight) / 2 + iconSize / 2
    }

    static func titleLineCenter(for node: ProjectNode) -> CGFloat {
        titleLineCenter(hasFilmstrip: !node.images.isEmpty)
    }

    static func isInteractive(node: ProjectNode, point: CGPoint, size: CGSize) -> Bool {
        guard !node.images.isEmpty else { return false }
        let stripTop = titleLineCenter(for: node) + iconSize / 2 + filmstripSpacing
        let stripBottom = stripTop + filmstripHeight
        return point.x >= filmstripLeading && point.x <= size.width - rowTrailing
            && point.y >= stripTop && point.y <= stripBottom
    }
}

/// App-specific row content. The shared Tree owns selection, disclosure, projection and drag/drop;
/// this view owns the project's folder/document glyphs, content count, and image strip.
struct ProjectTreeRow: View {
    let context: TreeRowContext<ProjectTreeItem>
    let mediaURL: (NodeContent) -> URL
    @State private var editingTitle = ""
    @FocusState private var titleFieldFocused: Bool

    private var node: ProjectNode { context.node.value }

    var body: some View {
        if node.images.isEmpty {
            titleLine
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: ProjectTreeRowMetrics.filmstripSpacing) {
                titleLine.frame(height: ProjectTreeRowMetrics.iconSize)
                FilmstripScrubber(items: node.images, mediaURL: mediaURL)
                    .frame(height: ProjectTreeRowMetrics.filmstripHeight)
                    .padding(.leading, ProjectTreeRowMetrics.filmstripLeading)
                    .padding(.trailing, ProjectTreeRowMetrics.rowTrailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Image(systemName: node.children.isEmpty ? "doc.text" : "folder")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: ProjectTreeRowMetrics.iconSize, height: ProjectTreeRowMetrics.iconSize)
            if context.isEditing {
                TextField("Node name", text: $editingTitle)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onSubmit {
                        context.onCommitEditing(editingTitle)
                    }
            } else {
                Text(node.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if !node.content.isEmpty {
                Text("\(node.content.count)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, ProjectTreeRowMetrics.iconLeading)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
        .onAppear {
            editingTitle = node.title
            if context.isEditing { titleFieldFocused = true }
        }
        .onChange(of: context.isEditing) { _, isEditing in
            if isEditing {
                editingTitle = node.title
                titleFieldFocused = true
            } else {
                titleFieldFocused = false
            }
        }
        .onChange(of: node.id) { _, _ in editingTitle = node.title }
    }
}
