#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_COUNT=9
WINDOWS_PER_WORKSPACE=3
ROUNDS=20
WARMUP_ROUNDS=2
STRESS_DELAY_MS=10
SETUP_DELAY_MS=60

usage() {
    echo "usage: $0 workspace-switch [--rounds N] [--workspaces N] [--windows-per-workspace N] [--delay-ms N]"
    exit 1
}

die() {
    echo "perf-local: $1" >&2
    exit 1
}

require_accessibility() {
    swift -e 'import ApplicationServices; import Darwin; exit(AXIsProcessTrusted() ? 0 : 1)' \
        || die "Accessibility permission is required for the current terminal"
}

activate_fixture() {
    osascript -e 'tell application id "com.parket.harness" to activate' >/dev/null
    sleep 0.4
}

wait_for_perf_fixture() {
    local attempt
    for attempt in {1..20}; do
        if pgrep -x ParketHarnessApp >/dev/null \
            && PARKET_HARNESS_WINDOW_COUNT="$window_count" swift -swift-version 6 scripts/ax-perf-check.swift >/dev/null 2>&1
        then
            PARKET_HARNESS_WINDOW_COUNT="$window_count" swift -swift-version 6 scripts/ax-perf-check.swift
            return 0
        fi
        sleep 0.5
    done
    PARKET_HARNESS_WINDOW_COUNT="$window_count" swift -swift-version 6 scripts/ax-perf-check.swift >&2 || true
    return 1
}

prepare_workspace_switch() {
    activate_fixture
    swift -swift-version 6 scripts/send-hotkeys.swift setup \
        --workspaces "$WORKSPACE_COUNT" \
        --windows-per-workspace "$WINDOWS_PER_WORKSPACE" \
        --delay-ms "$SETUP_DELAY_MS"
}

run_cycles() {
    local rounds="$1"
    swift -swift-version 6 scripts/send-hotkeys.swift cycle \
        --workspaces "$WORKSPACE_COUNT" \
        --rounds "$rounds" \
        --delay-ms "$STRESS_DELAY_MS"
}

summarize_workspace_switch() {
    local trace="$1"
    local expected="$2"
    awk -v expected="$expected" '
    index($0, "\"name\":\"workspace_switch\"") {
        n++
        durations[n] = number_value($0, "duration_ms")
        queue_delays[n] = number_value($0, "queue_delay_ms")
        runs[n] = number_value($0, "run_ms")
        reads[n] = number_value($0, "ax_reads")
        writes[n] = number_value($0, "ax_writes")
        hides[n] = number_value($0, "hide_ms")
        retiles[n] = number_value($0, "retile_ms")
        focuses[n] = number_value($0, "focus_ms")
        duration_sum += durations[n]
        queue_sum += queue_delays[n]
        run_sum += runs[n]
        reads_sum += reads[n]
        writes_sum += writes[n]
        hide_sum += hides[n]
        retile_sum += retiles[n]
        focus_sum += focuses[n]
        hide_reads_sum += number_value($0, "hide_ax_reads")
        hide_writes_sum += number_value($0, "hide_ax_writes")
        retile_reads_sum += number_value($0, "retile_ax_reads")
        retile_writes_sum += number_value($0, "retile_ax_writes")
        focus_reads_sum += number_value($0, "focus_ax_reads")
        focus_writes_sum += number_value($0, "focus_ax_writes")
    }
    function number_value(line, key,    marker, start, rest) {
        marker = "\"" key "\":"
        start = index(line, marker)
        if (start == 0) return 0
        rest = substr(line, start + length(marker))
        sub(/[,}].*/, "", rest)
        return rest + 0
    }
    function sort_numbers(values, count,    i, j, tmp) {
        for (i = 2; i <= count; i++) {
            tmp = values[i]
            j = i - 1
            while (j >= 1 && values[j] > tmp) {
                values[j + 1] = values[j]
                j--
            }
            values[j + 1] = tmp
        }
    }
    function percentile(values, count, p,    idx) {
        idx = int((count - 1) * p + 0.999999) + 1
        if (idx < 1) idx = 1
        if (idx > count) idx = count
        return values[idx]
    }
    END {
        if (n == 0) {
            print "perf-local: no workspace_switch trace samples"
            exit 1
        }
        sort_numbers(durations, n)
        sort_numbers(queue_delays, n)
        sort_numbers(runs, n)
        sort_numbers(hides, n)
        sort_numbers(retiles, n)
        sort_numbers(focuses, n)
        printf "workspace_switch samples: %d expected=%d\n", n, expected
        printf "duration_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f\n", \
            percentile(durations, n, 0.50), percentile(durations, n, 0.95), durations[n], duration_sum / n
        printf "queue_delay_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f\n", \
            percentile(queue_delays, n, 0.50), percentile(queue_delays, n, 0.95), queue_delays[n], queue_sum / n
        printf "run_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f\n", \
            percentile(runs, n, 0.50), percentile(runs, n, 0.95), runs[n], run_sum / n
        printf "hide_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            percentile(hides, n, 0.50), percentile(hides, n, 0.95), hides[n], hide_sum / n, hide_reads_sum / n, hide_writes_sum / n
        printf "retile_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            percentile(retiles, n, 0.50), percentile(retiles, n, 0.95), retiles[n], retile_sum / n, retile_reads_sum / n, retile_writes_sum / n
        printf "focus_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            percentile(focuses, n, 0.50), percentile(focuses, n, 0.95), focuses[n], focus_sum / n, focus_reads_sum / n, focus_writes_sum / n
        printf "ax_reads mean=%.1f\n", reads_sum / n
        printf "ax_writes mean=%.1f\n", writes_sum / n
    }' "$trace"
}

run_workspace_switch() {
    require_accessibility

    if pgrep -x parket >/dev/null; then
        die "parket must be stopped before perf-local"
    fi

    make build
    local bundle
    bundle=$(bash scripts/build-fixture-app.sh)
    local executable="$bundle/Contents/MacOS/ParketHarnessApp"
    local timestamp tmp_dir trace tmp_home
    timestamp=$(date +%Y-%m-%d-%H%M%S)
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/parket-perf.XXXXXX")
    trace="perf-workspace-switch-$timestamp.jsonl"
    tmp_home="$tmp_dir/home"
    window_count=$((WORKSPACE_COUNT * WINDOWS_PER_WORKSPACE))
    mkdir -p "$tmp_home"
    : >"$trace"

    pkill -x ParketHarnessApp 2>/dev/null || true
    sleep 1

    PARKET_HARNESS_MODE=workspace-switch PARKET_HARNESS_WINDOW_COUNT="$window_count" "$executable" >/dev/null 2>&1 &
    local fixture_pid=$!
    HOME="$tmp_home" PARKET_TRACE_PATH="$trace" PARKET_MANAGED_BUNDLE_ID=com.parket.harness .build/release/parket &
    local parket_pid=$!

    trap "kill $parket_pid 2>/dev/null || true; kill $fixture_pid 2>/dev/null || true; pkill -x ParketHarnessApp 2>/dev/null || true; rm -rf '$tmp_dir'" EXIT

    wait_for_perf_fixture || die "fixture did not become ready"
    sleep 2
    kill -0 "$parket_pid"

    prepare_workspace_switch
    : >"$trace"
    run_cycles "$WARMUP_ROUNDS"
    sleep 0.5
    : >"$trace"
    run_cycles "$ROUNDS"
    sleep 0.5

    summarize_workspace_switch "$trace" "$((WORKSPACE_COUNT * ROUNDS))"
    echo "trace: $trace"
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage
shift

case "$cmd" in
    workspace-switch)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --rounds)
                    ROUNDS="$2"
                    shift 2
                    ;;
                --iterations)
                    ROUNDS="$2"
                    shift 2
                    ;;
                --workspaces)
                    WORKSPACE_COUNT="$2"
                    shift 2
                    ;;
                --windows-per-workspace)
                    WINDOWS_PER_WORKSPACE="$2"
                    shift 2
                    ;;
                --delay-ms)
                    STRESS_DELAY_MS="$2"
                    shift 2
                    ;;
                *)
                    usage
                    ;;
            esac
        done
        run_workspace_switch
        ;;
    *)
        usage
        ;;
esac
