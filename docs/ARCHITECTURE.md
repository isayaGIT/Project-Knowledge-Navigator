# Architecture

## Domain and persistence
- `ProjectNode`: stable identity, title, recursive children, and content items. The model has no dependency on the component library.
- `NodeContent`: typed references to Markdown/text, annotated images, links, audio, video, and arbitrary local files. Binary media stays in project-scoped files.
- `ProjectStore`: owns local persistence, project selection, selected-node state, expanded IDs, and validated tree mutations.
- `ProjectKnowledgeWidget`: compact, read-mostly project summary and shortcuts.

## Shared Tree boundary
- `Cross-Project-Components/Sources/CrossProjectComponents/TreeView.swift` exposes the generic API and `TreeNodeRepresentable` protocol; `TreeProjection.swift` owns stable wrappers, ancestor-preserving filtering, and placement proposals; `TreeViewController.swift` owns the AppKit outline lifecycle, controlled selection/expansion synchronization, and row-content hosting.
- `ProjectTreeSidebar.swift`: app shell and adapter. It maps `ProjectNode` into `ProjectTreeItem`, binds selection and expanded IDs to `ProjectStore`, translates `TreeMovePlacement` to the app's `NodeMovePlacement`, rejects invalid moves through a non-mutating candidate-tree validation, and forwards accepted moves to the store.
- `TreeRowView.swift`: app-owned visual content—folder/document glyphs, content count, image filmstrip, row height, disclosure alignment, and filmstrip-only pointer hit testing. These details stay out of the generic component.
- The shared component owns interaction mechanics, not domain mutation or persistence. Its row builder accepts host-defined SwiftUI content; `searchableText` can differ from the visible title; `canMove` must be a pure legality check.

The app references the single local Swift Package at `../../../Cross-Project-Components`. `project.yml` is the source configuration for this dependency; regenerate the Xcode project with `LOGNAME=koripor USER=koripor xcodegen generate` in this environment when dependencies or source membership change.

## Filmstrip
The app and package still have separate `FilmstripScrubber` implementations. The Tree extraction intentionally leaves the app's tested media resolution and scrub behavior untouched; merging the two is a separate parity change that must prove visual and interaction compatibility first.

## Storage decision
Use versioned JSON manifests and project-scoped media files while they remain sufficient. Move storage behind the same store API to SQLite only if measured use requires concurrent writes, complex querying, or much larger node counts.

## Safety and scope
- Core use requires no network calls.
- Removing a node/media reference does not silently delete original files.
- The shared Tree has no host-app model, storage, WidgetKit, or third-party runtime dependency.
