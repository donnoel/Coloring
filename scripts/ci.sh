#!/bin/bash
# Same build and test contract locally and on GitHub. No retries or disabled assertions.
set -euo pipefail
cd "$(dirname "$0")/.."
export TZ=UTC LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
phase="${1:-all}"
case "$phase" in environment|build|unit|ui|all) ;; *) echo "Usage: bash scripts/ci.sh {environment|build|unit|ui|all} <simulator-UDID>" >&2; exit 2 ;; esac
expected_xcode=26.6
project=Coloring.xcodeproj
scheme=Coloring
ui_target=ColoringUITests
actual_xcode="$(xcodebuild -version | sed -n '1p')"
if [[ "$actual_xcode" != "Xcode $expected_xcode" ]]; then
  echo "CI requires Xcode $expected_xcode; found $actual_xcode. Select it with DEVELOPER_DIR before running this check." >&2
  exit 2
fi
printf 'Commit: %s\nToolchain: %s\nDeveloper directory: %s\nTimezone: %s; test language/region: en/US\n' "$(git rev-parse HEAD)" "$actual_xcode" "$(xcode-select -p)" "$TZ"
simulator_id="${2:-}"
if [[ "$phase" != environment && -z "$simulator_id" ]]; then
  echo 'An installed simulator UDID is required.' >&2
  exit 2
fi
if [[ -n "$simulator_id" ]]; then
  python3 - "$simulator_id" 26.5 <<'PY_RUNTIME'
import json, subprocess, sys
runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '--json']))['runtimes']
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))['devices']
for runtime in runtimes:
    if any(device['udid'] == sys.argv[1] for device in devices.get(runtime['identifier'], [])):
        if not runtime.get('isAvailable') or runtime.get('version') != sys.argv[2]:
            raise SystemExit(f"CI requires simulator runtime {sys.argv[2]}; found {runtime.get('version')}.")
        print('Simulator runtime:', runtime['identifier'], runtime['version'])
        break
else:
    raise SystemExit('Simulator UDID was not found.')
PY_RUNTIME
fi
destination="platform=iOS Simulator,id=$simulator_id,arch=$(uname -m)"
if [[ "$phase" == environment ]]; then exit 0; fi
DERIVED_DATA="${DERIVED_DATA:-$PWD/DerivedData}"
RESULT_BUNDLE="${RESULT_BUNDLE:-${TMPDIR:-/tmp}/Coloring-$(uuidgen).xcresult}"
args=(
  -project "$project" -scheme "$scheme" -configuration Debug
  -destination "$destination" -derivedDataPath "$DERIVED_DATA"
)
build() {
  xcodebuild "${args[@]}" clean build-for-testing
}
run_tests() {
  local kind="$1"
  local state
  state="$(xcrun simctl list devices --json | python3 -c 'import json,sys; print(next(d["state"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"] == sys.argv[1]))' "$simulator_id")"
  if [[ "$state" != Booted ]]; then xcrun simctl boot "$simulator_id"; fi
  xcrun simctl bootstatus "$simulator_id" -b
  local selection=()
  if [[ "$kind" == unit ]]; then selection=("-skip-testing:$ui_target"); else selection=("-only-testing:$ui_target"); fi
  local result="${RESULT_BUNDLE%.xcresult}-$kind.xcresult"
  mkdir -p "$(dirname "$result")"
  xcodebuild "${args[@]}" -resultBundlePath "$result" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -testLanguage en -testRegion US "${selection[@]}" test-without-building
}
case "$phase" in
  build) build ;;
  unit|ui) run_tests "$phase" ;;
  all) build; run_tests unit; run_tests ui ;;
esac
