# Project Knowledge Navigator

A local-first macOS workspace for organizing project knowledge as an infinitely nestable hierarchy of nodes. Nodes can contain child nodes and mixed content; image collections appear directly inside their node row as a continuous, draggable filmstrip.

## Principles
- The nested node structure is the primary interface—not a conventional folder-only tree.
- No fixed nesting depth. Any node may have children and its own content.
- The filmstrip itself is the scrubber: click or drag directly on the visible frames to seek across the full image collection. No separate progress slider or carousel buttons.
- Project documents and media remain local and portable.
- The macOS app is the editor; the desktop widget is a compact entry point.

## Status
Initial scaffold. See `docs/SPEC.md` and `docs/ARCHITECTURE.md`.

## Build
Requires macOS, Xcode, and XcodeGen:

```sh
xcodegen generate
xcodebuild -project ProjectKnowledgeNavigator.xcodeproj -scheme ProjectKnowledgeNavigator -destination 'platform=macOS' build
```
