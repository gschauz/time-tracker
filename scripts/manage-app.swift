import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let manager = Foundation.FileManager.default
let allowedIDs: Set<String> = ["com.garret.timetracker", "com.garret.timetracker.preview"]
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
func url(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }
func validate(_ path: URL) {
    guard let id = Bundle(url: path)?.bundleIdentifier, allowedIDs.contains(id) else {
        fail("Refusing to change an unrecognized application: \(path.path)")
    }
}

guard let action = arguments.first else { fail("Missing action") }
do {
    switch action {
    case "stop":
        let paths = Set(arguments.dropFirst().map { url($0) })
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard let path = app.bundleURL?.standardizedFileURL else { return false }
            return paths.contains(path) && allowedIDs.contains(app.bundleIdentifier ?? "")
        }
        for app in apps {
            guard app.terminate() else { fail("Time Tracker could not quit. Finish any open form and retry.") }
        }
        let deadline = Date().addingTimeInterval(12)
        while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard apps.allSatisfy(\.isTerminated) else {
            fail("Time Tracker is still open. Update stopped without force-quitting it.")
        }
    case "install":
        guard arguments.count == 4 else { fail("install requires staged app, target, and rollback paths") }
        let source = url(arguments[1]), target = url(arguments[2]), rollback = url(arguments[3])
        validate(source)
        guard !manager.fileExists(atPath: rollback.path) else { fail("A rollback copy already exists; inspect it before updating.") }
        let incoming = target.deletingLastPathComponent().appendingPathComponent(".Time Tracker.incoming-\(UUID().uuidString).app")
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: source, to: incoming)
        if manager.fileExists(atPath: target.path) {
            validate(target)
            try manager.moveItem(at: target, to: rollback)
        }
        do { try manager.moveItem(at: incoming, to: target) }
        catch {
            if manager.fileExists(atPath: rollback.path) { try? manager.moveItem(at: rollback, to: target) }
            try? manager.removeItem(at: incoming)
            throw error
        }
    case "trash":
        for path in arguments.dropFirst().map({ url($0) }) where manager.fileExists(atPath: path.path) {
            // Do not follow the convenient output link back to the installed app.
            if (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            validate(path)
            try manager.trashItem(at: path, resultingItemURL: nil)
        }
    case "rollback":
        guard arguments.count == 3 else { fail("rollback requires target and previous app paths") }
        let target = url(arguments[1]), previous = url(arguments[2])
        validate(previous)
        if manager.fileExists(atPath: target.path) { validate(target); try manager.trashItem(at: target, resultingItemURL: nil) }
        try manager.moveItem(at: previous, to: target)
    default: fail("Unknown action")
    }
} catch { fail(error.localizedDescription) }
