# Time Tracker release workflow

The user wants one current installed app, automatic cleanup of replaced copies, and real source version history.

- The everyday app lives only at `~/Documents/Codex/Applications/Time Tracker.app`. Never launch a separate development bundle for everyday use. The output `Time Tracker.app` is a symbolic link to the installed app, not another copy.
- Preserve `~/Library/Application Support/TimeTracker/` and the `com.garret.timetracker` preferences. Never remove user project data as part of app cleanup.
- Before each user-facing release, increment `VERSION` (patch for ordinary changes, minor for features) and `BUILD_NUMBER`. Show the version in About and the footer menu.
- Use the local Git repository for source history. Commit the intended source changes before building and tag `v<VERSION>` only after the installed release is verified. Do not store built apps or personal tracking data in Git. Do not push or publish without authorization.
- Run the appropriate checks, then `bash scripts/update.sh`. That script builds a candidate, gracefully quits the current app, installs in place, relaunches, verifies the live process/version/data load, updates the ZIP, and moves obsolete app bundles to Trash. Never force-quit an app with unsaved work or a pending save failure. Inspect and preserve an active editing form before updating.
- `scripts/build.sh` is for compilation only; it creates a temporary staged app. A successful build is not a completed user-facing update. Do not leave the old process running and ask the user to restart routinely.
- If a test-preview bundle is necessary, keep it in `work`, use the preview bundle ID and demo data, quit it after testing, and remove it during the release. No leftover old or preview apps in the managed Applications folder or outputs.
- Verify the running app reports the expected version and canonical path before saying the update is complete. Keep only the latest `Time Tracker.zip` in outputs. Older source versions remain available through Git without duplicate installed apps.
