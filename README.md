# Time Tracker

A small native macOS app for freelance projects. Built with SwiftUI and AppKit, using the macOS system font (San Francisco) and the dark palette of Window Organizer. No account, network service, or third-party dependencies.

## Open the app

Open **Time Tracker** from Applications. The `Time Tracker.app` link beside this source folder points to that same installed copy. This build targets Apple silicon Macs running macOS 13 or later and is locally signed. Find the current version in **Time Tracker → About Time Tracker** or the bottom **…** menu.

## Track a project

- **New Project** creates a separate project with an optional client or description.
- Click a project’s header or chevron to expand or collapse it. Its name, status, and total remain visible when collapsed; timers keep running. Each project’s open/closed state is remembered.
- Two or more projects with the same client automatically appear together under a small client heading. Click that heading to collapse or expand the entire group independently of its projects. Client matching ignores capitalization and extra spaces. Projects with no client stay separate.
- **Start** begins that project’s session. **Pause** freezes it; **Resume** continues it without counting the break.
- **Stop** finishes the session and adds it to history. It resets the current session clock while preserving the project’s total.
- **Add Time** records earlier work in hours and minutes, with an end date/time and an optional note. The entry starts that duration before the selected end time.
- The session count at the bottom of a project opens its history. Individual entries can be deleted after confirmation.
- The project’s **…** menu lets you rename it, export its time, or delete it after confirmation.

Each project is independent; multiple projects can run at once. If you do that, the combined Today figure sums their time, including overlapping intervals.

The stopwatch in the menu bar provides each project’s Start/Resume, Pause, Stop, and Add Time controls. A number beside the icon shows how many projects are running. Add Time opens the main window’s entry form.

Closing the main window keeps the app and timers running in the menu bar. Sleeping the Mac or quitting the app pauses all running projects. Wake/relaunch leaves them paused until you resume. Display sleep alone does not pause the timers.

Keyboard shortcuts: **⌘N** new project, **⌘0** show window, **⇧⌘E** export all time, **⌘Q** pause and quit.

## Storage and export

Data is saved locally to `~/Library/Application Support/TimeTracker/projects.json` after changes and every ten seconds while a timer runs. Writes are atomic. The previous saved version is retained as `projects.json.backup`. After an unexpected app exit, timers recover paused at the last saved checkpoint; at most the last ten seconds may be missing.

Use the bottom **… → Show Data in Finder** menu to locate these files. If existing data cannot be read, the app displays an error and disables changes instead of overwriting it. If saving fails, the app displays an error and offers Retry Save; quitting also warns about unsaved changes.

CSV export includes project, client, session ID, start/end timestamps, decimal hours, entry type, and note. Each uninterrupted work interval gets its own row, so breaks are never billed. Exports include elapsed time from unfinished sessions, marked **Unfinished**, without stopping any clocks. Timestamps include UTC timezone information. Project names, clients, and notes are escaped for spreadsheets.

## Build and test

Requires the macOS Command Line Tools with Swift 6 or newer (the tests use Swift Testing). Open `Package.swift` in Xcode to work on the project, or run:

```sh
bash scripts/build.sh
bash scripts/test.sh
```

The build script creates a temporary app in `../../work/swift-build/package` and applies an ad hoc local signature. Set `TIME_TRACKER_BUILD_DIR` to change the build directory. Distribution to other Macs would need Developer ID signing and notarization.

## Updates and source history

There is one everyday installation: `/Applications/Time Tracker.app`. Each release has a version in `VERSION` and an increasing number in `BUILD_NUMBER`. Source changes are committed to this local Git repository, and verified releases are tagged `v<VERSION>`. No remote publishing is configured.

For a user-facing update, finish or cancel any editing form, increment the version/build files, run the appropriate checks, and commit the source changes. Then run:

```sh
bash scripts/update.sh
git tag "v$(cat VERSION)"
```

The updater builds and verifies a candidate before gracefully quitting the old app, which saves and pauses timers. It replaces the app in Applications, relaunches it, and checks the **running app’s** version, location, and saved-data load. Only after verification does it move obsolete installed/development/preview bundles to Trash, refresh the output link, and replace the downloadable ZIP. A failed launch/data-load verification restores the previous installation when available. It never force-quits the app or removes project data.

The build script alone does not update a running app. Follow `AGENTS.md` for the full release workflow. Older source versions stay in Git for rollback; older application bundles are not kept alongside the current app.

The automated tests cover independent timers, pause/resume accounting, stop semantics, day boundaries, checkpoint recovery, file round trips and backups, corrupt-file protection, manual entries, and CSV escaping.

To preview example projects without touching saved data:

```sh
open -n "/Applications/Time Tracker.app" --args --demo
```

Demo changes are kept in memory and discarded on quit. Quit the demo instance after previewing; do not use it for real tracking.
