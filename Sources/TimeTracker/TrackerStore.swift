import AppKit
import Combine

enum Editor: Identifiable {
    case project(UUID?), manual(UUID), history(UUID)
    var id: String {
        switch self {
        case .project(let id): return "project-\(id?.uuidString ?? "new")"
        case .manual(let id): return "manual-\(id)"
        case .history(let id): return "history-\(id)"
        }
    }
}

final class TrackerStore: ObservableObject {
    @Published private(set) var data = TrackerData()
    @Published var now = Date()
    @Published var editor: Editor?
    @Published var error: String?
    @Published var notice: String?
    private(set) var loadFailed = false
    private let file: DataFile?
    private var ticker: AnyCancellable?
    private var ticks = 0

    var projects: [Project] { data.projects }
    var runningCount: Int { projects.filter(\.isRunning).count }
    var today: DateInterval { Calendar.current.dateInterval(of: .day, for: now)! }

    init(file: DataFile? = nil, demo: Bool = false) {
        self.file = file
        if demo {
            var first = Project(name: "Brand identity", client: "Studio North")
            first.sessions = [WorkSession(spans: [TimeSpan(start: now.addingTimeInterval(-86400), duration: 12420)])]
            first.start(at: now.addingTimeInterval(-2534))
            var second = Project(name: "Website design", client: "Studio North")
            second.sessions = [WorkSession(spans: [TimeSpan(start: now.addingTimeInterval(-172800), duration: 26100)])]
            second.start(at: now.addingTimeInterval(-7200))
            second.pause(at: now.addingTimeInterval(-5400))
            data.projects = [first, second, Project(name: "Monthly retainer", client: "Independent work")]
        } else if let file {
            do {
                data = try file.load()
                let recovered = data.projects.contains(where: \.isRunning)
                if recovered {
                    for index in data.projects.indices { data.projects[index].pause(at: min(data.checkpoint, now)) }
                    notice = "Your unfinished timers were paused at the last saved checkpoint. Resume when you’re ready."
                    save()
                }
            } catch {
                loadFailed = true
                self.error = "Couldn’t open saved time: \(error.localizedDescription) Your existing file has been left untouched."
            }
        }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self else { return }
            self.now = date
            self.ticks += 1
            if self.ticks % 10 == 0 && self.runningCount > 0 { self.save() }
        }
    }

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    func update(_ id: UUID, _ mutate: (inout Project, Date) -> Void) {
        guard !loadFailed, let index = data.projects.firstIndex(where: { $0.id == id }) else { return }
        now = Date()
        mutate(&data.projects[index], now)
        save()
    }
    func start(_ id: UUID) { update(id) { $0.start(at: $1) } }
    func pause(_ id: UUID) { update(id) { $0.pause(at: $1) } }
    func stop(_ id: UUID) { update(id) { $0.stop(at: $1) } }

    func saveProject(id: UUID?, name: String, client: String) {
        guard !loadFailed else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let id { update(id) { project, _ in project.name = name; project.client = client } }
        else { data.projects.append(Project(name: name, client: client)); save() }
    }

    func addTime(_ id: UUID, duration: TimeInterval, endedAt: Date, note: String) {
        guard duration.isFinite, duration > 0, endedAt <= Date().addingTimeInterval(1) else { return }
        update(id) { project, _ in
            project.sessions.append(WorkSession(spans: [TimeSpan(start: endedAt.addingTimeInterval(-duration), duration: duration)], note: note.trimmingCharacters(in: .whitespacesAndNewlines), manual: true))
        }
    }

    func deleteSession(_ projectID: UUID, sessionID: UUID) {
        update(projectID) { project, _ in project.sessions.removeAll { $0.id == sessionID } }
    }
    func deleteProject(_ id: UUID) {
        guard !loadFailed else { return }
        data.projects.removeAll { $0.id == id }
        save()
    }
    func pauseAll(reason: String? = nil) {
        guard !loadFailed else { return }
        now = Date()
        let hadRunning = runningCount > 0
        for index in data.projects.indices { data.projects[index].pause(at: now) }
        if hadRunning, let reason { notice = reason }
        save()
    }

    func save() {
        guard !loadFailed else { return }
        data.checkpoint = Date()
        guard let file else { return }
        do { try file.save(data); error = nil }
        catch { self.error = "Your latest changes couldn’t be saved: \(error.localizedDescription) Keep Time Tracker open and try again." }
    }

    func revealData() {
        guard let file else { return }
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
    }

    func exportCSV(projectID: UUID? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Time Tracker \(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        panel.title = "Export time entries"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVExport.make(projects: projects.filter { projectID == nil || $0.id == projectID }, now: Date()).write(to: url, atomically: true, encoding: .utf8)
        } catch { self.error = "Couldn’t export time: \(error.localizedDescription)" }
    }
}
