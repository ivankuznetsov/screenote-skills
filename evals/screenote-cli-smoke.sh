#!/bin/bash
# Verify the Screenote CLI snapshot contract without contacting Screenote.

set -euo pipefail
umask 077

SCREENOTE_CLI_REV=e960bf5cd40412d1f672b254407e7b192658ea57
TMP_DIR=$(mktemp -d /tmp/screenote-cli-smoke-XXXXXX)
chmod 700 "$TMP_DIR"
SERVER_PID=
stop_server() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=
  fi
}
cleanup() {
  stop_server
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v screenote >/dev/null 2>&1 || fail "screenote CLI is missing; install revision $SCREENOTE_CLI_REV"

binary_metadata=$(go version -m "$(command -v screenote)" 2>/dev/null) || fail "cannot inspect the screenote binary with go version -m"
grep -Fq "github.com/ivankuznetsov/screenote-cli" <<<"$binary_metadata" || fail "screenote binary is not built from the expected module"
grep -Fq "${SCREENOTE_CLI_REV:0:12}" <<<"$binary_metadata" || fail "screenote binary is not built from revision $SCREENOTE_CLI_REV"

help=$(screenote snapshot --help)
grep -Fq -- "--manifest" <<<"$help" || fail "screenote snapshot is missing --manifest"
grep -Fq -- "--wait" <<<"$help" || fail "screenote snapshot is missing --wait"

mkdir -p "$TMP_DIR/home" "$TMP_DIR/xdg"
base64 -d >"$TMP_DIR/capture-a.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
PNG
cp "$TMP_DIR/capture-a.png" "$TMP_DIR/capture-b.png"

cat >"$TMP_DIR/snapshot.json" <<'JSON'
{
  "version": 1,
  "git_commit": "e960bf5",
  "taken_at": "2026-07-13T12:00:00Z",
  "images": [
    {
      "page": "/smoke",
      "title": "CLI smoke",
      "file": "capture-a.png",
      "viewport": "desktop"
    },
    {
      "page": "/smoke/resume",
      "title": "CLI resume smoke",
      "file": "capture-b.png",
      "viewport": "desktop"
    }
  ]
}
JSON

run_isolated() {
  env \
    -u SCREENOTE_BASE_URL \
    -u SCREENOTE_TOKEN \
    -u SCREENOTE_PROJECT \
    HOME="$TMP_DIR/home" \
    XDG_CONFIG_HOME="$TMP_DIR/xdg" \
    screenote "$@"
}

set +e
run_isolated --project 7 snapshot --manifest "$TMP_DIR/snapshot.json" --wait 1s \
  >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"
status=$?
set -e

[ "$status" -eq 2 ] || fail "valid manifest should reach isolated missing-base-url gate (exit 2), got $status"
python3 - "$TMP_DIR/stderr" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
if payload.get("code") != "missing_base_url":
    raise SystemExit(f"valid manifest did not reach configuration gate: {payload}")
PY

manifest_sha=$(sha256sum "$TMP_DIR/snapshot.json" | cut -d' ' -f1)
capture_a_sha=$(sha256sum "$TMP_DIR/capture-a.png" | cut -d' ' -f1)
capture_b_sha=$(sha256sum "$TMP_DIR/capture-b.png" | cut -d' ' -f1)
timeout 20s python3 "$(dirname "$0")/fake-screenote-api.py" "$TMP_DIR/port" "$TMP_DIR/server-report.json" &
SERVER_PID=$!
for _ in $(seq 1 100); do
  [ -s "$TMP_DIR/port" ] && break
  kill -0 "$SERVER_PID" 2>/dev/null || fail "fake Screenote API exited before startup"
  sleep 0.05
done
[ -s "$TMP_DIR/port" ] || fail "fake Screenote API did not start"
base_url="http://127.0.0.1:$(cat "$TMP_DIR/port")"

run_snapshot() {
  run_isolated --base-url "$base_url" --token smoke-token --project 7 \
    snapshot --manifest "$TMP_DIR/snapshot.json" --wait 3s
}

set +e
run_snapshot >"$TMP_DIR/first-stdout" 2>"$TMP_DIR/first-stderr"
first_status=$?
set -e
[ "$first_status" -ne 0 ] || fail "first snapshot run should fail after a partial upload"
python3 - "$TMP_DIR/first-stdout" "$TMP_DIR/first-stderr" <<'PY'
import json
import pathlib
import sys

events = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
if [event["event"] for event in events] != ["snapshot_prepared", "image_uploaded"]:
    raise SystemExit(f"unexpected partial-run events: {events}")
error = json.loads(pathlib.Path(sys.argv[2]).read_text())
if error.get("code") != "upload_failed" or error.get("operation") != "upload_image" or error.get("manifest_entry") != 1:
    raise SystemExit(f"unexpected partial-run error: {error}")
PY

run_snapshot >"$TMP_DIR/resume-stdout" 2>"$TMP_DIR/resume-stderr" || fail "unchanged snapshot resume failed: $(cat "$TMP_DIR/resume-stderr")"
python3 - "$TMP_DIR/resume-stdout" "$TMP_DIR/server-report.json" <<'PY'
import json
import pathlib
import sys

events = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
ready = [event for event in events if event.get("event") == "snapshot_ready"]
if len(ready) != 1 or ready[0].get("state") != "ready" or not ready[0].get("review_url"):
    raise SystemExit(f"resume did not produce exactly one terminal ready event: {events}")
if events[-1] is not ready[0]:
    raise SystemExit(f"snapshot_ready was not the terminal event: {events}")
if not any(event.get("event") == "image_skipped" and event.get("manifest_entry") == 0 for event in events):
    raise SystemExit(f"resume did not skip the already-attached image: {events}")
report = json.loads(pathlib.Path(sys.argv[2]).read_text())
if report.get("prepare_calls") != 2 or not report.get("prepare_identical"):
    raise SystemExit(f"server did not observe identical manifest identity: {report}")
if report.get("uploads") != {"100": 1, "101": 2}:
    raise SystemExit(f"server did not observe partial upload plus resumed skip: {report}")
PY

[ "$(sha256sum "$TMP_DIR/snapshot.json" | cut -d' ' -f1)" = "$manifest_sha" ] || fail "manifest changed between retry attempts"
[ "$(sha256sum "$TMP_DIR/capture-a.png" | cut -d' ' -f1)" = "$capture_a_sha" ] || fail "first image changed between retry attempts"
[ "$(sha256sum "$TMP_DIR/capture-b.png" | cut -d' ' -f1)" = "$capture_b_sha" ] || fail "second image changed between retry attempts"

stop_server

absolute_path="$TMP_DIR/capture-a.png"
python3 - "$TMP_DIR/snapshot.json" "$absolute_path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["images"][0]["file"] = sys.argv[2]
path.write_text(json.dumps(payload))
PY

set +e
run_isolated --project 7 snapshot --manifest "$TMP_DIR/snapshot.json" --wait 1s \
  >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"
status=$?
set -e

[ "$status" -eq 2 ] || fail "absolute image path should fail manifest preflight (exit 2), got $status"
python3 - "$TMP_DIR/stderr" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = {"code": "invalid_file", "operation": "preflight", "manifest_entry": 0}
for key, value in expected.items():
    if payload.get(key) != value:
        raise SystemExit(f"unexpected invalid-path error: {payload}")
PY

echo "Screenote CLI contract smoke passed"
echo "- installed revision: $SCREENOTE_CLI_REV"
echo "- valid relative PNG manifest: accepted before configuration"
echo "- partial failure: resumed unchanged identity and skipped attached bytes"
echo "- absolute image path: rejected by JSON preflight contract"
