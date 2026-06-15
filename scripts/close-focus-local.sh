#!/usr/bin/env bash
set -euo pipefail

SETTLE_DELAY=0.18

die() {
    echo "close-focus-local: $1" >&2
    exit 1
}

require_accessibility() {
    swift -e 'import ApplicationServices; import Darwin; exit(AXIsProcessTrusted() ? 0 : 1)' \
        || die "Accessibility permission is required for the current terminal"
}

screen_count() {
    swift -e 'import AppKit; print(NSScreen.screens.count)'
}

focus_title() {
    swift -swift-version 6 scripts/ax-focus-check.swift focus "$1" --timeout-ms 2500 >/dev/null
    sleep "$SETTLE_DELAY"
}

close_title() {
    swift -swift-version 6 scripts/ax-focus-check.swift close "$1"
    sleep "$SETTLE_DELAY"
}

expect_title() {
    swift -swift-version 6 scripts/ax-focus-check.swift expect "$1" --timeout-ms 3000
}

wait_for_fixture() {
    local attempt
    for attempt in {1..30}; do
        if pgrep -x ParketHarnessApp >/dev/null \
            && swift -swift-version 6 scripts/ax-focus-check.swift expect-count 3 --timeout-ms 500 >/dev/null 2>&1
        then
            swift -swift-version 6 scripts/ax-focus-check.swift expect-count 3 --timeout-ms 5000
            return 0
        fi
        sleep 0.4
    done
    swift -swift-version 6 scripts/ax-focus-check.swift list >&2 || true
    return 1
}

run_close_focus_correctness() {
    require_accessibility

    if [[ "$(screen_count)" -lt 2 ]]; then
        echo "close-focus-local: skipped; requires at least two displays"
        return 0
    fi

    if pgrep -x parket >/dev/null; then
        die "parket must be stopped before close-focus-local"
    fi

    make build
    local bundle executable tmp_dir tmp_home
    bundle=$(bash scripts/build-fixture-app.sh)
    executable="$bundle/Contents/MacOS/ParketHarnessApp"
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/parket-close-focus.XXXXXX")
    tmp_home="$tmp_dir/home"
    mkdir -p "$tmp_home"

    pkill -x ParketHarnessApp 2>/dev/null || true
    sleep 1

    PARKET_HARNESS_MODE=multi-monitor-close "$executable" >/dev/null 2>&1 &
    local fixture_pid=$!
    HOME="$tmp_home" PARKET_MANAGED_BUNDLE_ID=com.parket.harness .build/release/parket &
    local parket_pid=$!

    trap "kill $parket_pid 2>/dev/null || true; kill $fixture_pid 2>/dev/null || true; pkill -x ParketHarnessApp 2>/dev/null || true; rm -rf '$tmp_dir'" EXIT

    wait_for_fixture || die "fixture did not become ready"
    sleep 2
    kill -0 "$parket_pid"

    focus_title "Close Secondary Active"
    close_title "Close Secondary Active"
    expect_title "Close Secondary Previous"

    echo "close-focus-local: completed"
}

run_close_focus_correctness
