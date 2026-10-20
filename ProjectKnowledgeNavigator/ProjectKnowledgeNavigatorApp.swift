import SwiftUI

@main
struct ProjectKnowledgeNavigatorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ProjectStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 520)
                .onChange(of: scenePhase) { _, phase in
                    // Preserve queued tree-move edits when the app/window is leaving
                    // the active scene; ordinary drag completion never blocks on disk.
                    if phase != .active { store.flushPendingPersistence() }
                }
                .onDisappear { store.flushPendingPersistence() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Node") { store.addChild(to: store.selectedNodeID) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
