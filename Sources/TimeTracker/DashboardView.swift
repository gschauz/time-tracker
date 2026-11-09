import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: TrackerStore
    @State private var deleting: Project?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = store.error { errorBanner(error) }
                    if let notice = store.notice {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle")
                            Text(notice).frame(maxWidth: .infinity, alignment: .leading)
                            Button { store.notice = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).clickCursor().accessibilityLabel("Dismiss notice")
                        }.font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            .padding(15).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if store.projects.isEmpty && !store.loadFailed { emptyState }
                    ForEach(ProjectSection.make(from: store.projects)) { section in
                        if section.client != nil {
                            ClientGroup(store: store, section: section, delete: { deleting = $0 })
                        } else {
                            ForEach(section.projects) { project in
                                ProjectCard(store: store, project: project, delete: { deleting = project })
                            }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
            footer
        }
        .background(LinearGradient(colors: [Color(white: 0.10), Color(white: 0.045)], startPoint: .leading, endPoint: .trailing).ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .tint(Theme.control)
        .sheet(item: $store.editor) { editor in
            switch editor {
            case .project(let id): ProjectEditor(store: store, projectID: id)
            case .manual(let id): ManualTimeEditor(store: store, projectID: id)
            case .history(let id): HistoryView(store: store, projectID: id)
            }
        }
        .alert("Delete \(deleting?.name ?? "project")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete Project", role: .destructive) {
                if let id = deleting?.id { store.deleteProject(id) }
                deleting = nil
            }
        } message: {
            Text("This removes the project and all its time entries. Export its history first if you need a copy.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "stopwatch.fill").font(.system(size: 28, weight: .medium)).accessibilityHidden(true)
                Text("Time Tracker").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button { store.editor = .project(nil) } label: { Label("New Project", systemImage: "plus") }
                    .buttonStyle(TrackerButtonStyle(primary: true))
                    .keyboardShortcut("n").disabled(store.loadFailed)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Your projects").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                if store.runningCount > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.green).frame(width: 5, height: 5)
                        Text("\(store.runningCount) running").font(.system(size: 11))
                    }.foregroundStyle(Theme.green)
                }
                Spacer()
                Text("Today").foregroundStyle(Theme.secondary)
                Text(TimeText.short(store.projects.reduce(0) { $0 + $1.duration(in: store.today, at: store.now) }))
                    .fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 12))
        }.padding(.horizontal, 30).padding(.top, 25).padding(.bottom, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Theme.canvas).frame(width: 86, height: 86)
                Image(systemName: "stopwatch").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.secondary)
            }.padding(.bottom, 4)
            Text("A little space for your time.").font(.system(size: 22, weight: .semibold))
            Text("Add a project, start its clock, and get to work.\nEach project keeps its own time.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button { store.editor = .project(nil) } label: { Label("Create your first project", systemImage: "plus") }
                .buttonStyle(TrackerButtonStyle(primary: true)).padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "\(store.runningCount > 0 ? "menubar.rectangle" : "internaldrive")")
            Text(store.runningCount > 0 ? "Timers keep running when you close this window" : "Saved on this Mac · Pauses when your Mac sleeps")
            Spacer()
            Menu {
                Button("Export All Time…") { store.exportCSV() }.disabled(store.projects.isEmpty)
                Button("Show Data in Finder", action: store.revealData)
                Divider()
                Button("Quit Time Tracker") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)) }
                .menuStyle(.borderlessButton).clickCursor().menuIndicator(.hidden).fixedSize().accessibilityLabel("More options")
        }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 30).padding(.vertical, 14)
            .background(Color.black.opacity(0.12))
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle").font(.system(size: 12))
            HStack {
                Button("Show Data in Finder", action: store.revealData)
                if !store.loadFailed { Button("Retry Save", action: store.save) }
            }.buttonStyle(TrackerButtonStyle(compact: true))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ClientGroup: View {
    @ObservedObject var store: TrackerStore
    let section: ProjectSection
    let delete: (Project) -> Void
    @AppStorage("collapsedClientGroups") private var collapsedClientGroups = "[]"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var collapsedIDs: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(collapsedClientGroups.utf8))) ?? [])
    }
    private var isExpanded: Bool { !collapsedIDs.contains(section.id) }
    private var total: TimeInterval { section.projects.reduce(0) { $0 + $1.total(at: store.now) } }
    private var runningCount: Int { section.projects.filter(\.isRunning).count }

    private func toggleExpanded() {
        var ids = collapsedIDs
        if isExpanded { ids.insert(section.id) } else { ids.remove(section.id) }
        guard let encoded = try? JSONEncoder().encode(ids.sorted()), let value = String(data: encoded, encoding: .utf8) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { collapsedClientGroups = value }
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: toggleExpanded) {
                HStack(spacing: 9) {
                    Text(section.client ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(section.projects.count) projects").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    if runningCount > 0 {
                        Circle().fill(Theme.green).frame(width: 5, height: 5)
                        Text("\(runningCount) running").font(.system(size: 10)).foregroundStyle(Theme.green)
                    }
                    Spacer(minLength: 8)
                    Text(TimeText.hours(total)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0)).frame(width: 16)
                }
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 5).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).clickCursor()
            .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") client \(section.client ?? "")")
            .accessibilityValue("\(section.projects.count) projects, \(TimeText.hours(total)) total, \(runningCount) running")
            .help(isExpanded ? "Collapse all projects for this client" : "Expand this client’s projects")
            if isExpanded {
                VStack(spacing: 18) {
                    ForEach(section.projects) { project in
                        ProjectCard(store: store, project: project, delete: { delete(project) })
                    }
                }
            }
        }
    }
}

struct ProjectCard: View {
    @ObservedObject var store: TrackerStore
    let project: Project
    let delete: () -> Void
    @AppStorage("collapsedProjectIDs") private var collapsedProjectIDs = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool {
        !collapsedProjectIDs.split(separator: ",").contains(Substring(project.id.uuidString))
    }

    private func toggleExpanded() {
        var ids = Set(collapsedProjectIDs.split(separator: ",").map(String.init))
        if isExpanded { ids.insert(project.id.uuidString) }
        else { ids.remove(project.id.uuidString) }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            collapsedProjectIDs = ids.sorted().joined(separator: ",")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 10) {
                                Text(project.name).font(.system(size: 22, weight: .semibold)).lineLimit(2)
                                StatusBadge(project: project)
                            }
                            Text(project.client.isEmpty ? "Personal project" : project.client)
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(TimeText.hours(project.total(at: store.now)))
                                .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                            Text("Total time").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).clickCursor()
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(project.name)")
                .accessibilityValue("\(project.isRunning ? "Running" : (project.isPaused ? "Paused" : "Ready")), \(TimeText.hours(project.total(at: store.now))) total")
                .help(isExpanded ? "Collapse project" : "Expand project")
                Menu {
                    Button("Edit Project…") { store.editor = .project(project.id) }
                    Button("Export Time…") { store.exportCSV(projectID: project.id) }
                    Divider()
                    Button("Delete Project…", role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis").frame(width: 18, height: 22) }
                    .menuStyle(.borderlessButton).clickCursor().menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Options for \(project.name)")
                    .padding(.leading, 6)
            }
            if isExpanded {
                details
            }
        }
        .padding(22).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var details: some View {
        VStack(spacing: 17) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.current == nil ? "SESSION" : "CURRENT SESSION")
                        .font(.system(size: 9, weight: .medium)).tracking(1.0).foregroundStyle(Theme.secondary)
                    Text(TimeText.clock(project.currentDuration(at: store.now)))
                        .font(.system(size: 29, weight: .medium)).monospacedDigit()
                        .foregroundStyle(project.isRunning ? Color.white : Theme.secondary)
                        .accessibilityLabel("Current session \(TimeText.clock(project.currentDuration(at: store.now)))")
                }
                Spacer(minLength: 0)
                TimerControls(store: store, project: project) { store.editor = .manual(project.id) }
            }.padding(17).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 13))
            HStack {
                Text("Today  \(TimeText.short(project.duration(in: store.today, at: store.now)))").monospacedDigit()
                Spacer()
                Button { store.editor = .history(project.id) } label: {
                    HStack(spacing: 5) {
                        Text("\(project.sessions.count) \(project.sessions.count == 1 ? "session" : "sessions")")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).clickCursor().help("View saved time entries")
            }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
    }
}
