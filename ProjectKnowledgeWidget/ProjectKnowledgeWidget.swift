import SwiftUI
import WidgetKit

struct ProjectWidgetEntry: TimelineEntry {
    let date: Date
    let projectName: String
    let projectID: String
    let nodeTitles: [String]
    let nodeIDs: [String]
}

struct ProjectWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProjectWidgetEntry {
        ProjectWidgetEntry(date: .now, projectName: "Project", projectID: "", nodeTitles: ["Rooms", "Design", "Furniture"], nodeIDs: ["", "", ""])
    }
    func getSnapshot(in context: Context, completion: @escaping (ProjectWidgetEntry) -> Void) { completion(loadEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProjectWidgetEntry>) -> Void) {
        completion(Timeline(entries: [loadEntry()], policy: .after(.now.addingTimeInterval(900))))
    }
    private func loadEntry() -> ProjectWidgetEntry {
        let defaults = UserDefaults(suiteName: "group.com.isayaGIT.ProjectKnowledgeNavigator")
        let name = defaults?.string(forKey: "currentProjectName") ?? "Project Knowledge"
        let projectID = defaults?.string(forKey: "currentProjectID") ?? ""
        let titles = defaults?.stringArray(forKey: "currentProjectNodeTitles") ?? ["Open app to select a project"]
        let ids = defaults?.stringArray(forKey: "currentProjectNodeIDs") ?? []
        return ProjectWidgetEntry(date: .now, projectName: name, projectID: projectID, nodeTitles: titles, nodeIDs: ids)
    }
}

struct ProjectWidgetView: View {
    var entry: ProjectWidgetProvider.Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(entry.projectName, systemImage: "square.stack.3d.up.fill").font(.headline).lineLimit(1)
            ForEach(Array(entry.nodeTitles.prefix(3).enumerated()), id: \.offset) { index, title in
                if index < entry.nodeIDs.count, !entry.projectID.isEmpty,
                   let url = URL(string: "pkn://open/\(entry.projectID)/\(entry.nodeIDs[index])") {
                    Link(destination: url) {
                        HStack(spacing: 6) { Image(systemName: "chevron.right").font(.caption2); Text(title).font(.caption).lineLimit(1) }
                    }.foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) { Image(systemName: "chevron.right").font(.caption2); Text(title).font(.caption).lineLimit(1) }.foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text("Project Knowledge Navigator").font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding().containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "pkn://open/\(entry.projectID)/\(entry.nodeIDs.first ?? "")"))
    }
}

@main struct ProjectKnowledgeWidget: Widget {
    let kind = "ProjectKnowledgeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProjectWidgetProvider()) { entry in ProjectWidgetView(entry: entry) }
            .configurationDisplayName("Project Knowledge")
            .description("Quick access to your current project.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
