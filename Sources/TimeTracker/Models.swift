import Foundation

struct TimeSpan: Codable, Equatable {
    var start: Date
    var duration: TimeInterval
    var end: Date { start.addingTimeInterval(duration) }

    func overlap(with interval: DateInterval) -> TimeInterval {
        max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
    }
}

struct WorkSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var spans: [TimeSpan] = []
    var note = ""
    var manual = false
    var duration: TimeInterval { spans.reduce(0) { $0 + $1.duration } }
    var start: Date { spans.first?.start ?? .distantPast }
    var end: Date { spans.last?.end ?? .distantPast }
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var client = ""
    var createdAt = Date()
    var sessions: [WorkSession] = []
    var current: WorkSession?
    var runningSince: Date?

    var isRunning: Bool { runningSince != nil }
    var isPaused: Bool { current != nil && runningSince == nil }

    func currentDuration(at now: Date) -> TimeInterval {
        (current?.duration ?? 0) + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func total(at now: Date) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration } + currentDuration(at: now)
    }

    func duration(in interval: DateInterval, at now: Date) -> TimeInterval {
        let saved = (sessions + [current].compactMap { $0 }).flatMap(\.spans)
            .reduce(0) { $0 + $1.overlap(with: interval) }
        let live = runningSince.map { TimeSpan(start: $0, duration: max(0, now.timeIntervalSince($0))).overlap(with: interval) } ?? 0
        return saved + live
    }

    mutating func start(at now: Date) {
        guard !isRunning else { return }
        if current == nil { current = WorkSession() }
        runningSince = now
    }

    mutating func pause(at now: Date) {
        guard let start = runningSince else { return }
        let elapsed = max(0, now.timeIntervalSince(start))
        if current == nil { current = WorkSession() }
        if elapsed > 0 { current?.spans.append(TimeSpan(start: start, duration: elapsed)) }
        runningSince = nil
    }

    mutating func stop(at now: Date) {
        pause(at: now)
        if let session = current, session.duration > 0 { sessions.append(session) }
        current = nil
    }
}

struct TrackerData: Codable {
    var version = 1
    var checkpoint = Date()
    var projects: [Project] = []

    func validate() throws {
        guard version == 1 else { throw DataError.unsupportedVersion }
        guard Set(projects.map(\.id)).count == projects.count else { throw DataError.invalidData }
        for project in projects {
            guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  project.runningSince == nil || project.current != nil else { throw DataError.invalidData }
            for session in project.sessions + [project.current].compactMap({ $0 }) {
                guard session.spans.allSatisfy({ $0.duration.isFinite && $0.duration >= 0 }) else { throw DataError.invalidData }
            }
        }
    }
}

struct ProjectSection: Identifiable {
    let id: String
    let client: String?
    let projects: [Project]

    static func make(from projects: [Project]) -> [ProjectSection] {
        func key(_ project: Project) -> String {
            project.client.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }
        let clients = Dictionary(grouping: projects.filter { !key($0).isEmpty }, by: key)
        var includedClients = Set<String>()
        var sections: [ProjectSection] = []
        for project in projects {
            let clientKey = key(project)
            if let group = clients[clientKey], group.count > 1 {
                guard includedClients.insert(clientKey).inserted else { continue }
                sections.append(ProjectSection(id: "client:" + clientKey,
                                               client: group[0].client.split(whereSeparator: \.isWhitespace).joined(separator: " "),
                                               projects: group))
            } else {
                sections.append(ProjectSection(id: "project:" + project.id.uuidString, client: nil, projects: [project]))
            }
        }
        return sections
    }
}

enum DataError: LocalizedError {
    case unsupportedVersion, invalidData
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This data was created by a newer version of Time Tracker."
        case .invalidData: return "The saved time data could not be validated."
        }
    }
}

struct DataFile {
    let url: URL
    func load() throws -> TrackerData {
        guard FileManager.default.fileExists(atPath: url.path) else { return TrackerData() }
        let result = try JSONDecoder().decode(TrackerData.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }

    func save(_ data: TrackerData) throws {
        try data.validate()
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        if manager.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            _ = try JSONDecoder().decode(TrackerData.self, from: previous)
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try encoded.write(to: url, options: .atomic)
    }
}

enum TimeText {
    static func clock(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration).rounded(.down))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
    static func hours(_ duration: TimeInterval) -> String {
        String(format: "%.2f h", max(0, duration) / 3600)
    }
    static func short(_ duration: TimeInterval) -> String {
        let minutes = Int(max(0, duration) / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

enum CSVExport {
    static func field(_ value: String) -> String {
        // Avoid spreadsheet formula execution when client names or notes are opened in Excel.
        let risky = value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
        let safe = risky ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func make(projects: [Project], now: Date) -> String {
        let iso = ISO8601DateFormatter()
        var rows = ["Project,Client,Session,Start,End,Hours,Type,Note"]
        for var project in projects {
            project.pause(at: now)
            let sessions = project.sessions + [project.current].compactMap { $0 }
            for session in sessions {
                // Export work intervals separately so pauses never appear as billable time.
                for span in session.spans {
                    let status = session.id == project.current?.id ? "Unfinished" : (session.manual ? "Manual" : "Tracked")
                    let values = [project.name, project.client, session.id.uuidString,
                                  iso.string(from: span.start), iso.string(from: span.end),
                                  String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), span.duration / 3600), status, session.note]
                    rows.append(values.map(field).joined(separator: ","))
                }
            }
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
}
