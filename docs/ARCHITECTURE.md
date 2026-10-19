# Architecture

## Minimal shape
- `ProjectNode`: stable identity, title, children, and content items; recursive nesting is not represented by fixed-depth fields.
- `NodeContent`: typed references to Markdown/text and local media. Binary media stays in files.
- `ProjectStore`: owns local persistence and selected-project state; views do not write files independently.
- `NodeTreeView`: renders hierarchy and routes actions to the store.
- `FilmstripScrubber`: row-level view maps pointer position to an index across the entire image collection and renders a moving thumbnail window. No separate slider.
- `ProjectKnowledgeWidget`: compact, read-mostly project summary and shortcuts.

## Storage decision
Start with a versioned JSON manifest because it is transparent, inspectable, and sufficient for the initial model. Keep media in files referenced by relative path. If real usage later requires concurrent writes, complex querying, or very large node counts, move storage behind the same API to SQLite. Do not add a database before it solves a measured problem.

## Interaction
Normalize pointer x-position to the strip width and map it to `[0, imageCount - 1]`; drag updates continuously. The visible thumbnail window follows the selected index while retaining neighboring frames as context. Stable media IDs—not array offsets—identify persisted items.

## Safety and scope
- No network calls required for core use.
- Removing a node/media reference does not silently delete original files.
- Avoid speculative abstractions and third-party runtime dependencies.
