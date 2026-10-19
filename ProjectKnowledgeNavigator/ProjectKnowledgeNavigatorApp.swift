import SwiftUI

@main
struct ProjectKnowledgeNavigatorApp: App {
    @StateObject private var store = ProjectStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Node") { store.addChild(to: store.selectedNodeID) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
