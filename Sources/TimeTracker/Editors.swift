import SwiftUI

struct ProjectEditor: View {
    @ObservedObject var store: TrackerStore
    let projectID: UUID?
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var client = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(projectID == nil ? "New Project" : "Edit Project").font(.system(size: 23, weight: .semibold))
                Text("A separate clock for a separate piece of work.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Project name").font(.system(size: 12, weight: .medium))
                TextField("e.g. Website redesign", text: $name).textFieldStyle(.roundedBorder).focused($focused)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Client or description (optional)").font(.system(size: 12, weight: .medium))
                TextField("e.g. Studio North", text: $client).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(TrackerButtonStyle())
                Button(projectID == nil ? "Create Project" : "Save Changes") {
                    store.saveProject(id: projectID, name: name, client: client)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(TrackerButtonStyle(primary: true))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.top, 4)
        }.padding(28).frame(width: 420).background(Theme.card).preferredColorScheme(.dark)
            .onAppear {
                if let id = projectID, let project = store.project(id) { name = project.name; client = project.client }
                focused = true
            }
    }
}

struct ManualTimeEditor: View {
    @ObservedObject var store: TrackerStore
    let projectID: UUID
    @Environment(\.dismiss) var dismiss
    @State private var hours = "0"
    @State private var minutes = "30"
    @State private var endedAt = Date()
    @State private var note = ""
    @FocusState private var focused: Bool

    private var duration: TimeInterval? {
        guard let h = Int(hours), let m = Int(minutes), h >= 0, h <= 99999, m >= 0, m < 60, h + m > 0 else { return nil }
        return Double(h * 3600 + m * 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Add Time").font(.system(size: 23, weight: .semibold))
                Text(store.project(projectID)?.name ?? "Project").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hours").font(.system(size: 12, weight: .medium))
                    TextField("0", text: $hours).textFieldStyle(.roundedBorder).focused($focused)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Minutes").font(.system(size: 12, weight: .medium))
                    TextField("0", text: $minutes).textFieldStyle(.roundedBorder)
                }
            }
            DatePicker("Ended at", selection: $endedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text("Note (optional)").font(.system(size: 12, weight: .medium))
                TextField("What did you work on?", text: $note).textFieldStyle(.roundedBorder)
            }
            Text("Adds a completed entry to this project. Its current timer keeps its own time.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if duration == nil {
                Text("Enter hours and 0–59 minutes, with a total greater than zero.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(TrackerButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Add Time") {
                    if let duration { store.addTime(projectID, duration: duration, endedAt: endedAt, note: note); dismiss() }
                }.buttonStyle(TrackerButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
                    .disabled(duration == nil || endedAt > Date())
            }
        }.padding(28).frame(width: 420).background(Theme.card).preferredColorScheme(.dark)
            .onAppear { focused = true }
    }
}

struct HistoryView: View {
    @ObservedObject var store: TrackerStore
    let projectID: UUID
    @Environment(\.dismiss) var dismiss
    @State private var deleting: UUID?
    private var project: Project? { store.project(projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Time history").font(.system(size: 23, weight: .semibold))
                    Text(project?.name ?? "Project").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(TimeText.hours(project?.total(at: store.now) ?? 0)).font(.system(size: 23, weight: .semibold)).monospacedDigit()
            }
            if project?.current != nil {
                Label("The current session appears here when you press Stop.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if project?.sessions.isEmpty ?? true {
                        VStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 30, weight: .light))
                            Text("No completed sessions yet.")
                            Text("Finish a timer or add time to see it here.").font(.system(size: 12))
                        }.foregroundStyle(Theme.secondary).frame(maxWidth: .infinity).padding(.vertical, 65)
                    }
                    ForEach((project?.sessions ?? []).sorted { $0.start > $1.start }) { session in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: session.manual ? "plus.circle" : "stopwatch").foregroundStyle(Theme.secondary).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.start.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12, weight: .medium))
                                Text("\(session.manual ? "Added manually" : "Tracked") · Ended \(session.end.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                if !session.note.isEmpty { Text(session.note).font(.system(size: 12)).textSelection(.enabled) }
                            }
                            Spacer()
                            Text(TimeText.clock(session.duration)).font(.system(size: 14, weight: .medium)).monospacedDigit()
                            Button { deleting = session.id } label: { Image(systemName: "trash").foregroundStyle(Theme.secondary) }
                                .buttonStyle(.plain).clickCursor().help("Delete this entry").accessibilityLabel("Delete time entry")
                        }.padding(15).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.frame(height: 300)
            HStack {
                Button("Export CSV…") { store.exportCSV(projectID: projectID) }
                    .buttonStyle(TrackerButtonStyle()).disabled((project?.sessions.isEmpty ?? true) && project?.current == nil)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(TrackerButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 560).background(Theme.card).preferredColorScheme(.dark)
            .alert("Delete this time entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete Entry", role: .destructive) {
                    if let deleting { store.deleteSession(projectID, sessionID: deleting) }
                    deleting = nil
                }
            } message: { Text("This time will be removed from the project’s total.") }
    }
}
