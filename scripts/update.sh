#!/bin/bash
# Install one canonical app, relaunch it, and verify the running release before cleanup.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$(dirname "$ROOT")"
SCRATCH="${TIME_TRACKER_BUILD_DIR:-$ROOT/../../work/swift-build}"
mkdir -p "$SCRATCH"
SCRATCH="$(cd "$SCRATCH" && pwd)"
APP="$HOME/Documents/Codex/Applications/Time Tracker.app"
STAGED="$SCRATCH/package/Time Tracker.app"
PREVIOUS="$(dirname "$APP")/.Time Tracker.previous.app"
LEGACY="$OUTPUT/Time Tracker.app"
PREVIEW="$ROOT/../../work/Time Tracker Preview.app"
STATUS="$SCRATCH/update-status.json"
VERSION="$(cat "$ROOT/VERSION")"
BUILD="$(cat "$ROOT/BUILD_NUMBER")"
export CLANG_MODULE_CACHE_PATH="$SCRATCH/module-cache"
export TIME_TRACKER_BUILD_DIR="$SCRATCH"
export TIME_TRACKER_APP_PATH="$STAGED"
manage_app() { swift -target "$(uname -m)-apple-macosx13.0" "$ROOT/scripts/manage-app.swift" "$@"; }

restore_previous() {
    manage_app stop "$APP"
    if [[ -d "$PREVIOUS" ]]; then
        manage_app rollback "$APP" "$PREVIOUS"
        open "$APP"
    elif [[ -d "$LEGACY" && ! -L "$LEGACY" ]]; then
        manage_app trash "$APP"
        open "$LEGACY"
    elif [[ -d "$APP" ]]; then
        open "$APP"
    fi
}

if [[ -d "$APP" ]]; then
    INSTALLED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
    if (( BUILD <= INSTALLED_BUILD )); then
        echo 'Increment VERSION and BUILD_NUMBER before publishing a new update.' >&2
        exit 1
    fi
fi

bash "$ROOT/scripts/build.sh"
codesign --verify --deep --strict "$STAGED"
manage_app stop "$APP" "$LEGACY" "$PREVIEW"
if ! manage_app install "$STAGED" "$APP" "$PREVIOUS"; then
    restore_previous
    exit 1
fi
rm -f "$STATUS"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true
if ! open "$APP" --args --update-status-file "$STATUS"; then
    restore_previous
    exit 1
fi
for ((attempt=0; attempt<15; attempt++)); do
    [[ -f "$STATUS" ]] && break
    sleep 1
done
if ! python3 - "$STATUS" "$APP" "$VERSION" "$BUILD" <<'PY'
import json, os, sys
try:
    status = json.load(open(sys.argv[1]))
    assert status['appPath'] == sys.argv[2]
    assert status['version'] == sys.argv[3] and status['build'] == sys.argv[4]
    assert not status['loadFailed']
    os.kill(status['pid'], 0)
    print(f"Verified Time Tracker {status['version']} ({status['build']}); {status['projectCount']} saved projects loaded.")
except Exception as error:
    print(f'Could not verify the new running app: {error}', file=sys.stderr)
    sys.exit(1)
PY
then
    restore_previous
    exit 1
fi

# Keep one portable download and one installed app. Old bundles go to Trash only after verification.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/Time Tracker.zip"
manage_app trash "$PREVIOUS" "$LEGACY" "$PREVIEW" "$STAGED"
if [[ ! -e "$LEGACY" && ! -L "$LEGACY" ]]; then ln -s "$APP" "$LEGACY"; fi
echo "Installed and running: $APP"
