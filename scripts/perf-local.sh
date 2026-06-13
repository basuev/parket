#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_COUNT=9
WINDOWS_PER_WORKSPACE=3
ROUNDS=20
WARMUP_ROUNDS=2
STRESS_DELAY_MS=10
SETUP_DELAY_MS=60
APP_INSTANCES=1
NATIVE_TABS=0
CHURN=0
FOCUS_THRASH=0
DISTRIBUTE_SCREENS=0
SCENARIO_LABEL=workspace-switch
THRESHOLDS=0
MAX_DURATION_P95_MS=18
MAX_CHURN_DURATION_P95_MS=35
MAX_QUEUE_P95_MS=5

usage() {
    echo "usage: $0 workspace-switch|matrix [--rounds N] [--workspaces N] [--windows-per-workspace N] [--delay-ms N] [--app-instances N] [--native-tabs] [--churn] [--focus-thrash] [--distribute-screens] [--label NAME] [--thresholds] [--max-duration-p95-ms N] [--max-churn-duration-p95-ms N] [--max-queue-p95-ms N]"
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
            && PARKET_HARNESS_EXPECTED_STANDARD_COUNT="$expected_standard_count" swift -swift-version 6 scripts/ax-perf-check.swift >/dev/null 2>&1
        then
            PARKET_HARNESS_EXPECTED_STANDARD_COUNT="$expected_standard_count" swift -swift-version 6 scripts/ax-perf-check.swift
            return 0
        fi
        sleep 0.5
    done
    PARKET_HARNESS_EXPECTED_STANDARD_COUNT="$expected_standard_count" swift -swift-version 6 scripts/ax-perf-check.swift >&2 || true
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
    local duration_budget="$MAX_DURATION_P95_MS"
    if [[ "$CHURN" == "1" || "$SCENARIO_LABEL" == "churn" ]]; then
        duration_budget="$MAX_CHURN_DURATION_P95_MS"
    fi
    awk -v expected="$expected" \
        -v thresholds="$THRESHOLDS" \
        -v duration_budget="$duration_budget" \
        -v queue_budget="$MAX_QUEUE_P95_MS" '
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
        frontmost_checks[n] = number_value($0, "frontmost_check_ms")
        activates[n] = number_value($0, "activate_ms")
        focused_window_reads[n] = number_value($0, "focused_window_read_ms")
        raises[n] = number_value($0, "raise_ms")
        explicit_focus_attrs[n] = number_value($0, "explicit_focus_attrs_ms")
        duration_sum += durations[n]
        queue_sum += queue_delays[n]
        run_sum += runs[n]
        reads_sum += reads[n]
        writes_sum += writes[n]
        hide_sum += hides[n]
        retile_sum += retiles[n]
        focus_sum += focuses[n]
        frontmost_check_sum += frontmost_checks[n]
        activate_sum += activates[n]
        focused_window_read_sum += focused_window_reads[n]
        raise_sum += raises[n]
        explicit_focus_attrs_sum += explicit_focus_attrs[n]
        hide_reads_sum += number_value($0, "hide_ax_reads")
        hide_writes_sum += number_value($0, "hide_ax_writes")
        retile_reads_sum += number_value($0, "retile_ax_reads")
        retile_writes_sum += number_value($0, "retile_ax_writes")
        focus_reads_sum += number_value($0, "focus_ax_reads")
        focus_writes_sum += number_value($0, "focus_ax_writes")
        frontmost_check_reads_sum += number_value($0, "frontmost_check_ax_reads")
        frontmost_check_writes_sum += number_value($0, "frontmost_check_ax_writes")
        activate_reads_sum += number_value($0, "activate_ax_reads")
        activate_writes_sum += number_value($0, "activate_ax_writes")
        focused_window_read_reads_sum += number_value($0, "focused_window_read_ax_reads")
        focused_window_read_writes_sum += number_value($0, "focused_window_read_ax_writes")
        raise_reads_sum += number_value($0, "raise_ax_reads")
        raise_writes_sum += number_value($0, "raise_ax_writes")
        explicit_focus_attrs_reads_sum += number_value($0, "explicit_focus_attrs_ax_reads")
        explicit_focus_attrs_writes_sum += number_value($0, "explicit_focus_attrs_ax_writes")
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
        sort_numbers(frontmost_checks, n)
        sort_numbers(activates, n)
        sort_numbers(focused_window_reads, n)
        sort_numbers(raises, n)
        sort_numbers(explicit_focus_attrs, n)
        duration_p50 = percentile(durations, n, 0.50)
        duration_p95 = percentile(durations, n, 0.95)
        queue_p50 = percentile(queue_delays, n, 0.50)
        queue_p95 = percentile(queue_delays, n, 0.95)
        run_p50 = percentile(runs, n, 0.50)
        run_p95 = percentile(runs, n, 0.95)
        hide_p50 = percentile(hides, n, 0.50)
        hide_p95 = percentile(hides, n, 0.95)
        retile_p50 = percentile(retiles, n, 0.50)
        retile_p95 = percentile(retiles, n, 0.95)
        focus_p50 = percentile(focuses, n, 0.50)
        focus_p95 = percentile(focuses, n, 0.95)
        frontmost_check_p50 = percentile(frontmost_checks, n, 0.50)
        frontmost_check_p95 = percentile(frontmost_checks, n, 0.95)
        activate_p50 = percentile(activates, n, 0.50)
        activate_p95 = percentile(activates, n, 0.95)
        focused_window_read_p50 = percentile(focused_window_reads, n, 0.50)
        focused_window_read_p95 = percentile(focused_window_reads, n, 0.95)
        raise_p50 = percentile(raises, n, 0.50)
        raise_p95 = percentile(raises, n, 0.95)
        explicit_focus_attrs_p50 = percentile(explicit_focus_attrs, n, 0.50)
        explicit_focus_attrs_p95 = percentile(explicit_focus_attrs, n, 0.95)
        printf "workspace_switch samples: %d expected=%d\n", n, expected
        printf "duration_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f\n", \
            duration_p50, duration_p95, durations[n], duration_sum / n
        printf "queue_delay_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f\n", \
            queue_p50, queue_p95, queue_delays[n], queue_sum / n
        printf "run_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f\n", \
            run_p50, run_p95, runs[n], run_sum / n
        printf "hide_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            hide_p50, hide_p95, hides[n], hide_sum / n, hide_reads_sum / n, hide_writes_sum / n
        printf "retile_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            retile_p50, retile_p95, retiles[n], retile_sum / n, retile_reads_sum / n, retile_writes_sum / n
        printf "focus_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            focus_p50, focus_p95, focuses[n], focus_sum / n, focus_reads_sum / n, focus_writes_sum / n
        printf "frontmost_check_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            frontmost_check_p50, frontmost_check_p95, frontmost_checks[n], frontmost_check_sum / n, frontmost_check_reads_sum / n, frontmost_check_writes_sum / n
        printf "activate_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            activate_p50, activate_p95, activates[n], activate_sum / n, activate_reads_sum / n, activate_writes_sum / n
        printf "focused_window_read_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            focused_window_read_p50, focused_window_read_p95, focused_window_reads[n], focused_window_read_sum / n, focused_window_read_reads_sum / n, focused_window_read_writes_sum / n
        printf "raise_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            raise_p50, raise_p95, raises[n], raise_sum / n, raise_reads_sum / n, raise_writes_sum / n
        printf "explicit_focus_attrs_ms p50=%.1f p95=%.1f max=%.1f mean=%.1f ax_reads_mean=%.1f ax_writes_mean=%.1f\n", \
            explicit_focus_attrs_p50, explicit_focus_attrs_p95, explicit_focus_attrs[n], explicit_focus_attrs_sum / n, explicit_focus_attrs_reads_sum / n, explicit_focus_attrs_writes_sum / n
        printf "ax_reads mean=%.1f\n", reads_sum / n
        printf "ax_writes mean=%.1f\n", writes_sum / n
        if (thresholds == 1) {
            printf "thresholds duration_p95<=%.1f queue_p95<=%.1f samples==%d\n", duration_budget, queue_budget, expected
            if (n != expected) {
                printf "perf-local threshold failed: samples %d expected %d\n", n, expected > "/dev/stderr"
                failed = 1
            }
            if (duration_p95 > duration_budget) {
                printf "perf-local threshold failed: duration p95 %.1f > %.1f\n", duration_p95, duration_budget > "/dev/stderr"
                failed = 1
            }
            if (queue_p95 > queue_budget) {
                printf "perf-local threshold failed: queue p95 %.1f > %.1f\n", queue_p95, queue_budget > "/dev/stderr"
                failed = 1
            }
            if (failed == 1) exit 1
        }
    }' "$trace"
}

screen_count() {
    swift -e 'import AppKit; print(NSScreen.screens.count)'
}

run_matrix_case() {
    local label="$1"
    shift
    local threshold_args=()
    if [[ "$THRESHOLDS" == "1" ]]; then
        threshold_args+=(--thresholds)
    fi
    threshold_args+=(--max-duration-p95-ms "$MAX_DURATION_P95_MS")
    threshold_args+=(--max-churn-duration-p95-ms "$MAX_CHURN_DURATION_P95_MS")
    threshold_args+=(--max-queue-p95-ms "$MAX_QUEUE_P95_MS")
    echo "perf-local matrix: $label"
    bash "$0" workspace-switch --label "$label" "${threshold_args[@]}" "$@"
}

run_matrix() {
    run_matrix_case default --rounds 20 --workspaces 9 --windows-per-workspace 3 --delay-ms 10
    run_matrix_case large-9x8 --rounds 8 --workspaces 9 --windows-per-workspace 8 --delay-ms 10
    run_matrix_case multi-app --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --app-instances 2
    run_matrix_case native-tabs --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --native-tabs
    run_matrix_case churn --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --churn
    run_matrix_case focus-thrash --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --focus-thrash

    if [[ "$(screen_count)" -gt 1 ]]; then
        run_matrix_case multi-monitor --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --distribute-screens
    else
        echo "perf-local matrix: multi-monitor skipped, only one display is available"
    fi
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
    expected_standard_count=$((window_count * APP_INSTANCES))
    if [[ "$NATIVE_TABS" == "1" ]]; then
        expected_standard_count=$((expected_standard_count * 2))
    fi
    mkdir -p "$tmp_home"
    : >"$trace"

    pkill -x ParketHarnessApp 2>/dev/null || true
    sleep 1

    local instance fixture_pid
    for instance in $(seq 1 "$APP_INSTANCES"); do
        PARKET_HARNESS_MODE=workspace-switch \
            PARKET_HARNESS_WINDOW_COUNT="$window_count" \
            PARKET_HARNESS_TITLE_PREFIX="$SCENARIO_LABEL $instance" \
            PARKET_HARNESS_NATIVE_TABS="$NATIVE_TABS" \
            PARKET_HARNESS_CHURN="$CHURN" \
            PARKET_HARNESS_FOCUS_THRASH="$FOCUS_THRASH" \
            PARKET_HARNESS_DISTRIBUTE_SCREENS="$DISTRIBUTE_SCREENS" \
            "$executable" >/dev/null 2>&1 &
        fixture_pid=$!
    done
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
    echo "scenario: $SCENARIO_LABEL"
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
                --app-instances)
                    APP_INSTANCES="$2"
                    shift 2
                    ;;
                --native-tabs)
                    NATIVE_TABS=1
                    shift
                    ;;
                --churn)
                    CHURN=1
                    shift
                    ;;
                --focus-thrash)
                    FOCUS_THRASH=1
                    shift
                    ;;
                --distribute-screens)
                    DISTRIBUTE_SCREENS=1
                    shift
                    ;;
                --label)
                    SCENARIO_LABEL="$2"
                    shift 2
                    ;;
                --thresholds|--fail-on-thresholds)
                    THRESHOLDS=1
                    shift
                    ;;
                --max-duration-p95-ms)
                    MAX_DURATION_P95_MS="$2"
                    shift 2
                    ;;
                --max-churn-duration-p95-ms)
                    MAX_CHURN_DURATION_P95_MS="$2"
                    shift 2
                    ;;
                --max-queue-p95-ms)
                    MAX_QUEUE_P95_MS="$2"
                    shift 2
                    ;;
                *)
                    usage
                    ;;
            esac
        done
        run_workspace_switch
        ;;
    matrix)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --thresholds|--fail-on-thresholds)
                    THRESHOLDS=1
                    shift
                    ;;
                --max-duration-p95-ms)
                    MAX_DURATION_P95_MS="$2"
                    shift 2
                    ;;
                --max-churn-duration-p95-ms)
                    MAX_CHURN_DURATION_P95_MS="$2"
                    shift 2
                    ;;
                --max-queue-p95-ms)
                    MAX_QUEUE_P95_MS="$2"
                    shift 2
                    ;;
                *)
                    usage
                    ;;
            esac
        done
        run_matrix
        ;;
    *)
        usage
        ;;
esac
