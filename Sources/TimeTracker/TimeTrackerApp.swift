import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: TrackerStore = {
        if CommandLine.arguments.contains("--demo") || Bundle.main.bundleIdentifier == "com.garret.timetracker.preview" {
            return TrackerStore(demo: true)
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeTracker", isDirectory: true)
        return TrackerStore(file: DataFile(url: directory.appendingPathComponent("projects.json")))
    }()
    private var dashboard: NSWindow?
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.store.pauseAll(reason: "Your timers paused when your Mac went to sleep. Resume a project when you’re ready.")
        }
        showDashboard()
        reportUpdateStatus()
    }

    private func reportUpdateStatus() {
        guard let index = CommandLine.arguments.firstIndex(of: "--update-status-file"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        do {
            let status: [String: Any] = ["appPath": Bundle.main.bundleURL.path,
                                       "pid": ProcessInfo.processInfo.processIdentifier,
                                       "version": AppVersion.version, "build": AppVersion.build,
                                       "projectCount": store.projects.count, "loadFailed": store.loadFailed]
            try JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]).write(to: destination, options: .atomic)
        } catch { NSLog("Could not report update status: %@", error.localizedDescription) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.pauseAll()
        if !store.loadFailed, let error = store.error {
            let alert = NSAlert()
            alert.messageText = "Your time hasn’t been saved"
            alert.informativeText = error
            alert.addButton(withTitle: "Keep Open")
            alert.addButton(withTitle: "Quit Anyway")
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
        return .terminateNow
    }

    func showDashboard() {
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Time Tracker"
            window.minSize = NSSize(width: 720, height: 470)
            window.setFrameAutosaveName("TimeTrackerDashboard")
            window.isReleasedWhenClosed = false
            Theme.configure(window)
            window.contentView = NSHostingView(rootView: DashboardView(store: store))
            window.center()
            dashboard = window
        }
        dashboard?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openEditor(_ editor: Editor) {
        showDashboard()
        // Let the menu-bar popover dismiss before presenting a sheet on the main window.
        DispatchQueue.main.async { self.store.editor = editor }
    }
}

@main
struct TimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: delegate.store, openDashboard: delegate.showDashboard, openEditor: delegate.openEditor)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Time Tracker") { NSApp.orderFrontStandardAboutPanel(nil) }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Project…") { delegate.openEditor(.project(nil)) }.keyboardShortcut("n")
                    .disabled(delegate.store.loadFailed)
                Button("Show Time Tracker", action: delegate.showDashboard).keyboardShortcut("0")
                Divider()
                Button("Export All Time…") { delegate.showDashboard(); delegate.store.exportCSV() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: TrackerStore
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.runningCount > 0 ? "stopwatch.fill" : "stopwatch")
            if store.runningCount > 0 { Text("\(store.runningCount)").monospacedDigit() }
        }.accessibilityLabel("Time Tracker, \(store.runningCount) running projects")
    }
}

struct MenuBarView: View {
    @ObservedObject var store: TrackerStore
    let openDashboard: () -> Void
    let openEditor: (Editor) -> Void
    @Environment(\.dismiss) private var dismiss

    private func show(_ editor: Editor? = nil) {
        dismiss()
        if let editor { openEditor(editor) } else { openDashboard() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Time Tracker", systemImage: "stopwatch.fill").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { show(.project(nil)) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).clickCursor().help("New project").accessibilityLabel("New project").disabled(store.loadFailed)
            }.padding(18)
            Divider().opacity(0.5)
            if store.error != nil || store.notice != nil {
                Button { show() } label: {
                    Label(store.error != nil ? "Your time needs attention. Open app." : (store.notice ?? ""), systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(store.error != nil ? Color.orange : Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(14)
                }.buttonStyle(.plain).clickCursor()
            }
            if store.projects.isEmpty {
                VStack(spacing: 12) {
                    Text("Make time for your next project.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Button("Create a Project") { show(.project(nil)) }.buttonStyle(TrackerButtonStyle(primary: true)).disabled(store.loadFailed)
                }.padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.projects) { project in
                            VStack(alignment: .leading, spacing: 11) {
                                HStack {
                                    Text(project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    StatusBadge(project: project)
                                }
                                HStack(alignment: .firstTextBaseline) {
                                    Text(TimeText.clock(project.currentDuration(at: store.now)))
                                        .font(.system(size: 23, weight: .medium)).monospacedDigit()
                                    Spacer()
                                    Text("\(TimeText.hours(project.total(at: store.now))) total")
                                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).monospacedDigit()
                                }
                                TimerControls(store: store, project: project, compact: true) { show(.manual(project.id)) }
                            }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(12)
                }.frame(height: min(CGFloat(store.projects.count) * 146 + 14, 470))
            }
            Divider().opacity(0.5)
            HStack {
                Button { show() } label: { Label("Open Time Tracker", systemImage: "macwindow") }
                    .buttonStyle(.plain).clickCursor().font(.system(size: 11))
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).clickCursor().help("Pause timers and quit").accessibilityLabel("Quit Time Tracker")
            }.foregroundStyle(Theme.secondary).padding(16)
        }.frame(width: 354).background(Theme.canvas).preferredColorScheme(.dark).foregroundStyle(.white)
    }
}
