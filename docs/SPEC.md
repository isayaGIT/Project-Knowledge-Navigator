# Product Specification — Project Knowledge Navigator

## Purpose
A native macOS app for navigating and maintaining project knowledge through one extensible, nested node structure.

## Core model
- A project contains a root node.
- A node has a stable ID, title, zero or more child nodes, and zero or more content items.
- Nesting has no application-imposed maximum depth.
- A node may simultaneously have children and content; it is not required to be either a folder or a file.
- Content can include Markdown/text, images, audio, video, and external links. A node may contain any number of media items.
- Topics such as `Rooms`, `Design`, `Furniture`, or `Lighting Design` are ordinary nodes, not fixed schema types. Do not require `Benchmarks`, `Skills`, or `References` wrapper folders.

## Primary interaction
- Main view: compact indented list with expandable/collapsible nodes.
- Indentation communicates hierarchy; visual depth does not constrain data depth.
- Each row shows the node title and a concise content-aware preview.
- Multiple images can appear directly in a node row as a filmstrip.
- The filmstrip itself is the scrubber. Clicking a point selects the corresponding position across the complete image sequence. Pressing and dragging scrubs continuously as the pointer moves. No separate slider, thumb, or previous/next controls are required.
- As collections grow, load thumbnails lazily and full-resolution media on demand.
- Other content uses a restrained preview: document title/icon, audio waveform, or video poster.

## Persistence and portability
- Project selection, node structure, ordering, and content references persist locally.
- Media remains in files; metadata references those files rather than embedding large binaries.
- Stable node IDs preserve identity when moving nodes.
- Save changes safely and recover after relaunch. Removing a reference must not silently delete the original file.
- Markdown and ordinary media formats remain readable outside the app.

## Desktop widget
- Shows the selected project and a small set of node shortcuts.
- Clicking a shortcut opens the app at the corresponding project/node.
- The widget is read-mostly; full hierarchy editing remains in the app.

## Scope discipline
Initial implementation focuses on node model, navigation, inline filmstrip interaction, local persistence, and a small widget. Defer sync, collaboration, plugin systems, mind-map editing, rich task management, and complex tagging.

## Acceptance criteria
1. Nodes nest recursively without a fixed depth limit.
2. A node can contain children and multiple media items simultaneously.
3. A node row can render multiple image thumbnails inline.
4. Clicking or dragging directly on the filmstrip maps pointer position to the corresponding image in the entire collection.
5. No separate progress slider or mandatory carousel buttons.
6. Project and node data survive app relaunch.
7. The app builds with supported Xcode and model/interaction behavior has tests.
