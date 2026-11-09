import SwiftUI
import AppKit

enum Theme {
    static let card = Color(white: 40.0 / 255)
    static let canvas = Color(white: 0.065)
    static let secondary = Color(white: 0.70)
    static let control = Color(white: 0.32)
    static let green = Color(red: 0.40, green: 0.85, blue: 0.55)

    static func configure(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = NSColor(white: 0.065, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
    }
}

struct TrackerButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(configuration: configuration, primary: primary, compact: compact)
    }
    private struct ButtonSurface: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let compact: Bool
        @Environment(\.isEnabled) var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: compact ? 11 : 13, weight: .medium))
                .padding(.horizontal, compact ? 10 : 15)
                .frame(height: compact ? 29 : 36)
                .background(RoundedRectangle(cornerRadius: compact ? 7 : 9)
                    .fill(primary ? Theme.control : Color.white.opacity(hovered ? 0.09 : 0.035)))
                .overlay(RoundedRectangle(cornerRadius: compact ? 7 : 9)
                    .strokeBorder(Color.white.opacity(primary ? 0.04 : 0.15), lineWidth: 1))
                .foregroundStyle(Color.white)
                .brightness(configuration.isPressed ? -0.08 : (hovered ? 0.045 : 0))
                .opacity(enabled ? 1 : 0.32)
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .onHover { hovered = $0 }
                .clickCursor()
        }
    }
}

struct TimerControls: View {
    @ObservedObject var store: TrackerStore
    let project: Project
    var compact = false
    let addTime: () -> Void

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Button { project.isRunning ? store.pause(project.id) : store.start(project.id) } label: {
                Label(project.isRunning ? "Pause" : (project.isPaused ? "Resume" : "Start"), systemImage: project.isRunning ? "pause.fill" : "play.fill")
                    .frame(minWidth: compact ? 54 : 67)
            }
            .buttonStyle(TrackerButtonStyle(primary: true, compact: compact))
            .help(project.isRunning ? "Pause this project’s current session" : "Start tracking this project")
            Button { store.stop(project.id) } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(TrackerButtonStyle(compact: compact))
            .disabled(project.current == nil)
            .help("Finish this session and save it to history. Your total time is kept.")
            Button(action: addTime) { Label("Add Time", systemImage: "plus") }
                .buttonStyle(TrackerButtonStyle(compact: compact))
                .help("Add time worked earlier")
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(store.loadFailed)
    }
}

struct StatusBadge: View {
    let project: Project
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(project.isRunning ? Theme.green : Theme.secondary.opacity(0.65)).frame(width: 5, height: 5)
            Text(project.isRunning ? "Running" : (project.isPaused ? "Paused" : "Ready"))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(project.isRunning ? Theme.green : Theme.secondary)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(project.isRunning ? Theme.green.opacity(0.08) : Color.white.opacity(0.04)))
    }
}
