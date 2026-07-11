#!/usr/bin/env bash
set -euo pipefail

make build
bundle=$(bash scripts/build-fixture-app.sh)
check_output=$(mktemp "${TMPDIR:-/tmp}/parket-smoke.XXXXXX")
fixture_pid=
parket_pid=

cleanup() {
    if [[ -n "$parket_pid" ]]; then
        kill "$parket_pid" 2>/dev/null || true
    fi
    if [[ -n "$fixture_pid" ]]; then
        kill "$fixture_pid" 2>/dev/null || true
    fi
    rm -f "$check_output"
}

trap cleanup EXIT

if ! swift -e 'import ApplicationServices; import Darwin; exit(AXIsProcessTrusted() ? 0 : 1)'; then
    echo "smoke-local requires Accessibility for the current terminal" >&2
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
            fixture_pid=$(pgrep -n -x ParketHarnessApp)
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
open -n --env PARKET_HARNESS_LIFECYCLE=1 "$bundle"
wait_for_fixture

PARKET_MANAGED_BUNDLE_ID=com.parket.harness .build/release/parket &
parket_pid=$!

sleep 3
kill -0 "$parket_pid"
swift -swift-version 6 scripts/ax-lifecycle-check.swift
check_fixture
cat "$check_output"

kill "$parket_pid"
wait "$parket_pid" 2>/dev/null || true
check_fixture
cat "$check_output"

kill "$fixture_pid" 2>/dev/null || true
wait "$fixture_pid" 2>/dev/null || true

echo "smoke-local: completed"
