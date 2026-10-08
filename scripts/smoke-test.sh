#!/bin/bash
# Exercise the packaged app's startup, live sampling, renderer, menu, and clean exit.
set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo "Usage: scripts/smoke-test.sh /path/to/速喵.app" >&2
    exit 2
fi

# Keep diagnostic reports outside source control and enforce a bounded runtime.
APP_DIRECTORY="$(cd "$1" && pwd)"
REPORT_DIRECTORY="${NETSPEED_SMOKE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/netspeed-smoke.XXXXXX")}"
mkdir -p "$REPORT_DIRECTORY"
/usr/bin/codesign --verify --strict "$APP_DIRECTORY"
python3 - "$APP_DIRECTORY/Contents/MacOS/NetSpeed" "$REPORT_DIRECTORY" <<'PY'
"""Run a bounded smoke process and validate its machine-readable result."""
import json
import pathlib
import subprocess
import sys

executable = pathlib.Path(sys.argv[1])
report_directory = pathlib.Path(sys.argv[2])
report = report_directory / "smoke-report.json"
log = report_directory / "smoke-process.log"
# Captured app output is limited to the test report; no environment is dumped.
with log.open("w", encoding="utf-8") as stream:
    try:
        completed = subprocess.run(
            [str(executable), "--smoke-test", "--smoke-report", str(report),
             "--render-preview", str(report_directory / "status-preview.png")],
            stdout=stream, stderr=subprocess.STDOUT, timeout=20, check=False,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit("Smoke test exceeded its 20-second startup limit")
if completed.returncode != 0:
    raise SystemExit(f"Smoke process failed ({completed.returncode}); log: {log}")
if not report.is_file():
    raise SystemExit("Smoke process produced no report")
result = json.loads(report.read_text(encoding="utf-8"))
if result.get("success") is not True:
    raise SystemExit(f"Smoke checks failed; report: {report}")
# Older bundles must not pass without exercising settings and the approved compact width.
required_checks = {
    "settingsConstruction", "refreshPreferenceSync", "loginItemReadOnly",
    "loginItemStatusMapped", "applicationIdentity", "applicationIcon",
    "compactStatusWidth",
}
checks = result.get("checks", {})
if any(checks.get(name) is not True for name in required_checks):
    raise SystemExit(f"Required smoke evidence is incomplete; report: {report}")
print(json.dumps(result, ensure_ascii=False, indent=2))
print(f"Report: {report}")
PY
