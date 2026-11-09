import Testing
import Foundation
@testable import TimeTracker

struct TimerTests {
    let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func testPauseResumeExcludesBreakAndStopKeepsTotal() {
        var project = Project(name: "Design")
        project.start(at: epoch)
        project.start(at: epoch.addingTimeInterval(50)) // Repeated start is harmless.
        project.pause(at: epoch.addingTimeInterval(600))
        expectEqual(project.currentDuration(at: epoch.addingTimeInterval(1000)), 600)
        project.start(at: epoch.addingTimeInterval(1200))
        project.stop(at: epoch.addingTimeInterval(1500))
        expectEqual(project.total(at: epoch.addingTimeInterval(2000)), 900)
        expectEqual(project.sessions.count, 1)
        expectNil(project.current)
        expectNil(project.runningSince)
        project.stop(at: epoch.addingTimeInterval(2500))
        expectEqual(project.sessions.count, 1)
        project.start(at: epoch.addingTimeInterval(3000))
        expectEqual(project.currentDuration(at: epoch.addingTimeInterval(3060)), 60)
        expectEqual(project.total(at: epoch.addingTimeInterval(3060)), 960)
    }

    @Test func testProjectsRunIndependently() {
        var one = Project(name: "One")
        var two = Project(name: "Two")
        one.start(at: epoch)
        two.start(at: epoch.addingTimeInterval(30))
        one.pause(at: epoch.addingTimeInterval(60))
        expectEqual(one.total(at: epoch.addingTimeInterval(120)), 60)
        expectEqual(two.total(at: epoch.addingTimeInterval(120)), 90)
        expectTrue(two.isRunning)
    }

    @Test func testTodaySplitsMidnightAndExcludesPausedTime() {
        let interval = DateInterval(start: epoch, duration: 86400)
        var project = Project(name: "Midnight")
        project.start(at: epoch.addingTimeInterval(-600))
        project.pause(at: epoch.addingTimeInterval(600))
        project.start(at: epoch.addingTimeInterval(1200))
        expectEqual(project.duration(in: interval, at: epoch.addingTimeInterval(1500)), 900)
        expectEqual(project.total(at: epoch.addingTimeInterval(1500)), 1500)
    }

    @Test func testPersistenceAndCrashRecoveryCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = DataFile(url: directory.appendingPathComponent("projects.json"))
        var project = Project(name: "Saved", client: "Client")
        project.start(at: epoch)
        let checkpoint = epoch.addingTimeInterval(120)
        try file.save(TrackerData(checkpoint: checkpoint, projects: [project]))
        var loaded = try file.load()
        loaded.projects[0].pause(at: loaded.checkpoint)
        expectEqual(loaded.projects[0].total(at: epoch.addingTimeInterval(10000)), 120)
        expectTrue(loaded.projects[0].isPaused)
        try file.save(loaded)
        expectTrue(FileManager.default.fileExists(atPath: file.url.appendingPathExtension("backup").path))
        expectEqual(try file.load().projects[0], loaded.projects[0])
    }

    @Test func testCorruptDataCannotBeSilentlyOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = DataFile(url: directory.appendingPathComponent("projects.json"))
        let broken = Data("not valid JSON".utf8)
        try broken.write(to: file.url)
        expectThrows(try file.load())
        expectThrows(try file.save(TrackerData()))
        expectEqual(try Data(contentsOf: file.url), broken)
    }

    @Test func testCSVExportsActualWorkIntervalsAndEscapesFields() {
        var project = Project(name: "=Formula", client: "A, \"Studio\"")
        project.start(at: epoch)
        project.pause(at: epoch.addingTimeInterval(3600))
        project.start(at: epoch.addingTimeInterval(7200))
        let csv = CSVExport.make(projects: [project], now: epoch.addingTimeInterval(9000))
        expectTrue(csv.contains("\"'=Formula\""))
        expectTrue(csv.contains("\"A, \"\"Studio\"\"\""))
        expectTrue(csv.contains("\"1.000000\""))
        expectTrue(csv.contains("\"0.500000\""))
        expectEqual(csv.components(separatedBy: "\r\n").count, 4)
        expectTrue(project.isRunning, "Export must not pause the real timer")
    }

    @Test func testManualTimeAndClockReversalCannotSubtractWork() {
        var project = Project(name: "Manual")
        project.sessions.append(WorkSession(spans: [TimeSpan(start: epoch, duration: 1800)], note: "Workshop", manual: true))
        project.start(at: epoch.addingTimeInterval(100))
        project.stop(at: epoch)
        expectEqual(project.total(at: epoch), 1800)
        expectEqual(project.sessions.count, 1)
        expectEqual(TimeText.clock(3661), "01:01:01")
        expectEqual(TimeText.clock(360000), "100:00:00")
    }

    @Test @MainActor func testStoreRecoversRunningTimersAndPersistsManualEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = DataFile(url: directory.appendingPathComponent("projects.json"))
        var project = Project(name: "Recovered")
        project.start(at: epoch)
        try file.save(TrackerData(checkpoint: epoch.addingTimeInterval(90), projects: [project]))
        let store = TrackerStore(file: file)
        expectTrue(store.projects[0].isPaused)
        expectEqual(store.projects[0].currentDuration(at: Date()), 90)
        expectTrue(store.notice != nil)
        store.addTime(project.id, duration: 1800, endedAt: epoch, note: "Research")
        expectEqual(store.projects[0].total(at: Date()), 1890)
        store.start(project.id)
        store.pauseAll(reason: "Sleep")
        let saved = try file.load()
        expectTrue(saved.projects[0].isPaused)
        expectEqual(saved.projects[0].sessions[0].note, "Research")
        expectEqual(store.notice, "Sleep")
    }

    @Test @MainActor func testStoreBlocksEditsWhenSavedDataIsUnreadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = DataFile(url: directory.appendingPathComponent("projects.json"))
        let original = Data("broken".utf8)
        try original.write(to: file.url)
        let store = TrackerStore(file: file)
        store.saveProject(id: nil, name: "Must not overwrite", client: "")
        store.pauseAll()
        expectTrue(store.loadFailed)
        expectTrue(store.error != nil)
        expectTrue(store.projects.isEmpty)
        expectEqual(try Data(contentsOf: file.url), original)
    }

    @Test func testClientGroupsIgnoreCaseAndWhitespaceAndPreserveOrder() {
        let first = Project(name: "Brand", client: " Studio   North ")
        let separate = Project(name: "Other", client: "Other Client")
        let second = Project(name: "Website", client: "studio north")
        let groups = ProjectSection.make(from: [first, separate, second])
        expectEqual(groups.count, 2)
        expectEqual(groups[0].client, "Studio North")
        expectEqual(groups[0].projects.map(\.id), [first.id, second.id])
        expectNil(groups[1].client)
        expectEqual(groups[1].projects.map(\.id), [separate.id])
    }

    @Test func testProjectsWithoutClientsAreNeverGroupedTogether() {
        let first = Project(name: "Personal")
        let second = Project(name: "Research", client: "  ")
        let groups = ProjectSection.make(from: [first, second])
        expectEqual(groups.count, 2)
        expectTrue(groups.allSatisfy { $0.client == nil && $0.projects.count == 1 })
    }

    @Test func testClientEditsRegroupProjectsWithoutChangingTimers() {
        var first = Project(name: "Brand", client: "Client")
        var second = Project(name: "Web", client: "Someone else")
        first.start(at: epoch)
        expectEqual(ProjectSection.make(from: [first, second]).count, 2)
        second.client = "Client"
        let grouped = ProjectSection.make(from: [first, second])
        expectEqual(grouped.count, 1)
        expectEqual(grouped[0].id, "client:client")
        expectTrue(grouped[0].projects[0].isRunning)
        expectEqual(grouped[0].projects[0].total(at: epoch.addingTimeInterval(60)), 60)
        second.client = ""
        expectEqual(ProjectSection.make(from: [first, second]).count, 2)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
private func expectNil<T>(_ actual: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == nil, sourceLocation: sourceLocation)
}
private func expectTrue(_ actual: Bool, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual, Comment(rawValue: message), sourceLocation: sourceLocation)
}
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) }
    catch { }
}
