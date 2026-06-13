#!/usr/bin/env bash
set -euo pipefail

FOCUS_ROUNDS=8
SETTLE_DELAY=0.18

die() {
    echo "focus-local: $1" >&2
    exit 1
}

require_accessibility() {
    swift -e 'import ApplicationServices; import Darwin; exit(AXIsProcessTrusted() ? 0 : 1)' \
        || die "Accessibility permission is required for the current terminal"
}

press_workspace() {
    swift -swift-version 6 scripts/send-hotkeys.swift press --workspace "$1" --delay-ms 20
    sleep "$SETTLE_DELAY"
}

move_focused_to_workspace() {
    swift -swift-version 6 scripts/send-hotkeys.swift press --workspace "$1" --shift --delay-ms 20
    sleep "$SETTLE_DELAY"
}

focus_title() {
    swift -swift-version 6 scripts/ax-focus-check.swift focus "$1" --timeout-ms 2000 >/dev/null
    sleep "$SETTLE_DELAY"
}

expect_title() {
    swift -swift-version 6 scripts/ax-focus-check.swift expect "$1" --timeout-ms 2500
}

wait_for_focus_fixture() {
    local attempt
    for attempt in {1..30}; do
        if pgrep -x ParketHarnessApp >/dev/null \
            && swift -swift-version 6 scripts/ax-focus-check.swift expect-count 5 --timeout-ms 500 >/dev/null 2>&1
        then
            swift -swift-version 6 scripts/ax-focus-check.swift expect-count 5 --timeout-ms 5000
            return 0
        fi
        sleep 0.4
    done
    swift -swift-version 6 scripts/ax-focus-check.swift list >&2 || true
    return 1
}

run_focus_correctness() {
    require_accessibility

    if pgrep -x parket >/dev/null; then
        die "parket must be stopped before focus-local"
    fi

    make build
    local bundle executable tmp_dir tmp_home trace
    bundle=$(bash scripts/build-fixture-app.sh)
    executable="$bundle/Contents/MacOS/ParketHarnessApp"
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/parket-focus.XXXXXX")
    tmp_home="$tmp_dir/home"
    trace="focus-local-$(date +%Y-%m-%d-%H%M%S).jsonl"
    mkdir -p "$tmp_home"
    : >"$trace"

    pkill -x ParketHarnessApp 2>/dev/null || true
    sleep 1

    PARKET_HARNESS_MODE=focus-check "$executable" >/dev/null 2>&1 &
    local fixture_pid=$!
    HOME="$tmp_home" PARKET_TRACE_PATH="$trace" PARKET_MANAGED_BUNDLE_ID=com.parket.harness .build/release/parket &
    local parket_pid=$!

    trap "kill $parket_pid 2>/dev/null || true; kill $fixture_pid 2>/dev/null || true; pkill -x ParketHarnessApp 2>/dev/null || true; rm -rf '$tmp_dir'" EXIT

    wait_for_focus_fixture || die "fixture did not become ready"
    sleep 2
    kill -0 "$parket_pid"

    focus_title "Focus Normal 2"
    move_focused_to_workspace 2
    focus_title "Focus Normal 3"
    move_focused_to_workspace 3
    focus_title "Focus Native B"
    move_focused_to_workspace 4
    focus_title "Focus Normal 1"

    local round
    for round in $(seq 1 "$FOCUS_ROUNDS"); do
        press_workspace 2
        expect_title "Focus Normal 2"
        press_workspace 3
        expect_title "Focus Normal 3"
        press_workspace 4
        expect_title "Focus Native B"
        press_workspace 1
        expect_title "Focus Normal 1"
    done

    echo "focus-local: rounds=$FOCUS_ROUNDS completed"
    echo "trace: $trace"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rounds)
            FOCUS_ROUNDS="$2"
            shift 2
            ;;
        *)
            die "usage: $0 [--rounds N]"
            ;;
    esac
done

run_focus_correctness
