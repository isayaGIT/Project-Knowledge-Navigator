import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var isTreeEditingActive = false

    var body: some View {
        NavigationSplitView {
            ProjectTreeSidebar(
                isTreeEditingActive: $isTreeEditingActive,
                onCreateProject: { showNewProject = true }
            )
        } detail: {
            ProjectDetailView(onInteraction: { isTreeEditingActive = false })
        }
        .navigationTitle(store.manifest.name)
        .onOpenURL { url in
            guard url.scheme == "pkn" else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            // pkn://open alone is the widget's app-launch action; the host is "open".
            guard parts.count >= 2,
                  let projectID = UUID(uuidString: parts[0]),
                  let nodeID = UUID(uuidString: parts[1]) else { return }
            store.open(projectID: projectID, nodeID: nodeID)
        }
        .alert("New Project", isPresented: $showNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") { store.createProject(named: newProjectName); newProjectName = "" }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        } message: { Text("Each project has its own independent node structure and local data.") }
    }
}
