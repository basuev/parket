#!/usr/bin/env bash
set -euo pipefail

make build
bundle=$(bash scripts/build-fixture-app.sh)
check_output=$(mktemp "${TMPDIR:-/tmp}/parket-smoke.XXXXXX")

if ! swift -e 'import ApplicationServices; import CoreGraphics; import Darwin; exit(AXIsProcessTrusted() && CGPreflightListenEventAccess() ? 0 : 1)'; then
    echo "smoke-local requires Accessibility and Input Monitoring for the current terminal" >&2
    exit 1
fi

if pgrep -x parket >/dev/null; then
    echo "smoke-local requires parket to be stopped first" >&2
    exit 1
fi

check_fixture() {
    swift -swift-version 6 scripts/ax-smoke-check.swift >"$check_output" 2>&1
}

wait_for_fixture() {
    local attempt
    for attempt in {1..20}; do
        if pgrep -x ParketHarnessApp >/dev/null && check_fixture; then
            cat "$check_output"
            return 0
        fi
        sleep 0.5
    done
    cat "$check_output" >&2
    return 1
}

pkill -x ParketHarnessApp 2>/dev/null || true
sleep 1
open "$bundle"
wait_for_fixture

.build/release/parket &
parket_pid=$!
trap 'kill "$parket_pid" 2>/dev/null || true; pkill -x ParketHarnessApp 2>/dev/null || true; rm -f "$check_output"' EXIT

sleep 3
kill -0 "$parket_pid"
check_fixture
cat "$check_output"

kill "$parket_pid"
wait "$parket_pid" 2>/dev/null || true
check_fixture
cat "$check_output"

echo "smoke-local: completed"
