#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_COUNT=9
WINDOWS_PER_WORKSPACE=3
ROUNDS=20
WARMUP_ROUNDS=2
STRESS_DELAY_MS=10
SETUP_DELAY_MS=100
SETTLE_MS=350
POLL_MS=2
TIMEOUT_MS=1500
APP_INSTANCES=1
NATIVE_TABS=0
CHURN=0
FOCUS_THRASH=0
DISTRIBUTE_SCREENS=0
TRACE_PARKET=0
SCENARIO_LABEL=workspace-switch

usage() {
    echo "usage: $0 parket|aerospace|compare|matrix [options]"
    echo "options: --rounds N --workspaces N --windows-per-workspace N --delay-ms N --app-instances N --native-tabs --churn --focus-thrash --distribute-screens --trace-parket --label NAME"
    echo "compare: $0 compare <parket-jsonl> <aerospace-jsonl>"
    exit 1
}

die() {
    echo "latency-compare: $1" >&2
    exit 1
}

require_accessibility() {
    swift -e 'import ApplicationServices; import Darwin; exit(AXIsProcessTrusted() ? 0 : 1)' \
        || die "Accessibility permission is required for the current terminal"
}

screen_count() {
    swift -e 'import AppKit; print(NSScreen.screens.count)'
}

parse_common_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rounds|--iterations)
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
            --setup-delay-ms)
                SETUP_DELAY_MS="$2"
                shift 2
                ;;
            --settle-ms)
                SETTLE_MS="$2"
                shift 2
                ;;
            --poll-ms)
                POLL_MS="$2"
                shift 2
                ;;
            --timeout-ms)
                TIMEOUT_MS="$2"
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
            --trace-parket)
                TRACE_PARKET=1
                shift
                ;;
            --label)
                SCENARIO_LABEL="$2"
                shift 2
                ;;
            *)
                usage
                ;;
        esac
    done
}

activate_fixture() {
    swift -e 'import AppKit; for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == "com.parket.harness" { app.activate() }' >/dev/null
    sleep 0.4
}

activate_fixture_pid() {
    local pid="$1"
    swift -e 'import AppKit; import Darwin; import Foundation; guard CommandLine.arguments.count > 1, let raw = Int32(CommandLine.arguments[1]), let app = NSRunningApplication(processIdentifier: raw) else { exit(1) }; app.activate(); Thread.sleep(forTimeInterval: 0.4)' "$pid" >/dev/null
}

wait_for_perf_fixture() {
    local attempt
    for attempt in {1..20}; do
        if pgrep -x ParketHarnessApp >/dev/null; then
            activate_fixture
        fi
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
    local setup_windows_per_workspace="${SETUP_WINDOWS_PER_WORKSPACE:-$WINDOWS_PER_WORKSPACE}"
    if [[ "$APP_INSTANCES" -gt 1 ]]; then
        local pid
        for pid in "${fixture_pids[@]}"; do
            activate_fixture_pid "$pid"
            swift -swift-version 6 scripts/send-hotkeys.swift setup \
                --workspaces "$WORKSPACE_COUNT" \
                --windows-per-workspace "$setup_windows_per_workspace" \
                --delay-ms "$SETUP_DELAY_MS"
        done
    else
        activate_fixture
        swift -swift-version 6 scripts/send-hotkeys.swift setup \
            --workspaces "$WORKSPACE_COUNT" \
            --windows-per-workspace "$setup_windows_per_workspace" \
            --delay-ms "$SETUP_DELAY_MS"
    fi
}

write_aerospace_config() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    {
        echo "config-version = 2"
        echo "start-at-login = false"
        echo "auto-reload-config = false"
        echo "after-startup-command = []"
        echo "enable-normalization-flatten-containers = true"
        echo "enable-normalization-opposite-orientation-for-nested-containers = true"
        echo "accordion-padding = 0"
        echo "default-root-container-layout = 'tiles'"
        echo "default-root-container-orientation = 'auto'"
        echo "on-focused-monitor-changed = []"
        echo "automatically-unhide-macos-hidden-apps = false"
        echo "persistent-workspaces = ['1', '2', '3', '4', '5', '6', '7', '8', '9']"
        echo "[gaps]"
        echo "inner.horizontal = 0"
        echo "inner.vertical = 0"
        echo "outer.left = 0"
        echo "outer.bottom = 0"
        echo "outer.top = 0"
        echo "outer.right = 0"
        echo "[[on-window-detected]]"
        echo "if.app-id = 'com.parket.harness'"
        echo "run = 'layout tiling'"
        echo "[[on-window-detected]]"
        echo "run = 'layout floating'"
        echo "[mode.main.binding]"
        echo "cmd-h = []"
        echo "cmd-alt-h = []"
        for workspace in $(seq 1 9); do
            echo "alt-$workspace = 'workspace $workspace'"
            echo "alt-shift-$workspace = 'move-node-to-workspace $workspace'"
        done
    } > "$path"
}

wait_for_aerospace() {
    local attempt
    for attempt in {1..50}; do
        if aerospace list-workspaces --focused >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    aerospace list-workspaces --focused >&2 || true
    return 1
}

ensure_aerospace_bindings() {
    local bindings
    bindings=$(aerospace config --get mode.main.binding --json 2>/dev/null || true)
    [[ "$bindings" == *'"alt-1"'* ]] || die "AeroSpace config must bind alt-1 for benchmark workspace switching"
    [[ "$bindings" == *'"alt-shift-2"'* ]] || die "AeroSpace config must bind alt-shift-2 for benchmark setup"
}

start_aerospace_if_needed() {
    local tmp_home="$1"
    if pgrep -x AeroSpace >/dev/null; then
        AEROSPACE_STARTED=0
        ensure_aerospace_bindings
        return
    fi

    local executable="${AEROSPACE_EXECUTABLE:-/Applications/AeroSpace.app/Contents/MacOS/AeroSpace}"
    [[ -x "$executable" ]] || die "AeroSpace is not running and executable was not found at $executable"

    write_aerospace_config "$tmp_home/.config/aerospace/aerospace.toml"
    HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" "$executable" >/dev/null 2>&1 &
    aerospace_pid=$!
    AEROSPACE_STARTED=1
    wait_for_aerospace || die "AeroSpace did not start"
    ensure_aerospace_bindings
}

start_fixture() {
    local executable="$1"
    local instance
    for instance in $(seq 1 "$APP_INSTANCES"); do
            PARKET_HARNESS_MODE=workspace-switch \
            PARKET_HARNESS_WINDOW_COUNT="$window_count" \
            PARKET_HARNESS_TITLE_PREFIX="$SCENARIO_LABEL $instance" \
            PARKET_HARNESS_MOVING_WINDOW_COUNT="$fixture_moving_window_count" \
            PARKET_HARNESS_NATIVE_TABS="$NATIVE_TABS" \
            PARKET_HARNESS_CHURN="$CHURN" \
            PARKET_HARNESS_FOCUS_THRASH="$FOCUS_THRASH" \
            PARKET_HARNESS_DISTRIBUTE_SCREENS="$DISTRIBUTE_SCREENS" \
            "$executable" >/dev/null 2>&1 &
        fixture_pids+=("$!")
    done
}

capture_map() {
    local map="$1"
    : > "$map"
    local native_group_args=()
    if [[ "$NATIVE_TABS" == "1" ]]; then
        native_group_args+=(--require-native-tab-groups)
    fi
    if [[ "$DISTRIBUTE_SCREENS" == "1" ]]; then
        native_group_args+=(--ignore-stable-visible-titles)
    fi
    swift -swift-version 6 scripts/workspace-latency-check.swift map \
        --workspaces "$WORKSPACE_COUNT" \
        --expected-window-count "$expected_standard_count" \
        --expected-titles-per-workspace "$expected_titles_per_workspace" \
        --settle-ms "$SETTLE_MS" \
        "${native_group_args[@]}" \
        --output "$map"
}

run_external_cycle() {
    local wm="$1"
    local map="$2"
    local output="$3"
    local rounds="$4"
    : > "$output"
    swift -swift-version 6 scripts/workspace-latency-check.swift cycle \
        --wm "$wm" \
        --scenario "$SCENARIO_LABEL" \
        --map "$map" \
        --workspaces "$WORKSPACE_COUNT" \
        --rounds "$rounds" \
        --delay-ms "$STRESS_DELAY_MS" \
        --timeout-ms "$TIMEOUT_MS" \
        --poll-ms "$POLL_MS" \
        --start-workspace 1 \
        --output "$output"
}

run_warmup_cycle() {
    local wm="$1"
    local map="$2"
    local output="$tmp_dir/warmup-$wm.jsonl"
    run_external_cycle "$wm" "$map" "$output" "$WARMUP_ROUNDS"
}

summarize_latency_file() {
    local file="$1"
    awk '
    index($0, "\"kind\":\"workspace_latency\"") {
        n++
        visible[n] = number_value($0, "visible_latency_ms")
        if (index($0, "\"focus_latency_ms\":null") == 0) {
            focus_count++
            focus[focus_count] = number_value($0, "focus_latency_ms")
            focus_sum += focus[focus_count]
        }
        result = string_value($0, "result")
        result_counts[result]++
        visible_sum += visible[n]
    }
    function number_value(line, key,    marker, start, rest) {
        marker = "\"" key "\":"
        start = index(line, marker)
        if (start == 0) return 0
        rest = substr(line, start + length(marker))
        sub(/[,}].*/, "", rest)
        return rest + 0
    }
    function string_value(line, key,    marker, start, rest) {
        marker = "\"" key "\":\""
        start = index(line, marker)
        if (start == 0) return ""
        rest = substr(line, start + length(marker))
        sub(/".*/, "", rest)
        return rest
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
            print "latency samples: 0"
            exit 1
        }
        sort_numbers(visible, n)
        printf "visible_latency_ms samples=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f mean=%.1f\n", \
            n, percentile(visible, n, 0.50), percentile(visible, n, 0.95), percentile(visible, n, 0.99), visible[n], visible_sum / n
        if (focus_count > 0) {
            sort_numbers(focus, focus_count)
            printf "focus_latency_ms samples=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f mean=%.1f\n", \
                focus_count, percentile(focus, focus_count, 0.50), percentile(focus, focus_count, 0.95), percentile(focus, focus_count, 0.99), focus[focus_count], focus_sum / focus_count
        } else {
            print "focus_latency_ms samples=0"
        }
        for (result in result_counts) {
            printf "result_%s=%d\n", result, result_counts[result]
        }
    }' "$file"
}

require_all_ok_samples() {
    local file="$1"
    awk '
    index($0, "\"kind\":\"workspace_latency\"") {
        n++
        result = string_value($0, "result")
        if (result != "ok") {
            bad++
            result_counts[result]++
        }
    }
    function string_value(line, key,    marker, start, rest) {
        marker = "\"" key "\":\""
        start = index(line, marker)
        if (start == 0) return ""
        rest = substr(line, start + length(marker))
        sub(/".*/, "", rest)
        return rest
    }
    END {
        if (n == 0) {
            print "latency-compare: correctness failed: no latency samples" > "/dev/stderr"
            exit 1
        }
        if (bad > 0) {
            message = "latency-compare: correctness failed:"
            for (result in result_counts) {
                message = message " result_" result "=" result_counts[result]
            }
            print message > "/dev/stderr"
            exit 1
        }
    }' "$file"
}

compare_latency_files() {
    local file1="$1"
    local file2="$2"
    [[ -f "$file1" ]] || die "file not found: $file1"
    [[ -f "$file2" ]] || die "file not found: $file2"
    require_all_ok_samples "$file1"
    require_all_ok_samples "$file2"

    awk '
    index($0, "\"kind\":\"workspace_latency\"") {
        wm = string_value($0, "wm")
        if (!(wm in seen)) {
            order[++wm_count] = wm
            seen[wm] = 1
        }
        n[wm]++
        result = string_value($0, "result")
        result_count[wm, result]++
        visible[wm, n[wm]] = number_value($0, "visible_latency_ms")
        visible_sum[wm] += visible[wm, n[wm]]
        if (index($0, "\"focus_latency_ms\":null") == 0) {
            focus_n[wm]++
            focus[wm, focus_n[wm]] = number_value($0, "focus_latency_ms")
            focus_sum[wm] += focus[wm, focus_n[wm]]
        }
    }
    function number_value(line, key,    marker, start, rest) {
        marker = "\"" key "\":"
        start = index(line, marker)
        if (start == 0) return 0
        rest = substr(line, start + length(marker))
        sub(/[,}].*/, "", rest)
        return rest + 0
    }
    function string_value(line, key,    marker, start, rest) {
        marker = "\"" key "\":\""
        start = index(line, marker)
        if (start == 0) return ""
        rest = substr(line, start + length(marker))
        sub(/".*/, "", rest)
        return rest
    }
    function sort_metric(metric, wm, count,    i, j, tmp) {
        for (i = 2; i <= count; i++) {
            tmp = metric[wm, i]
            j = i - 1
            while (j >= 1 && metric[wm, j] > tmp) {
                metric[wm, j + 1] = metric[wm, j]
                j--
            }
            metric[wm, j + 1] = tmp
        }
    }
    function percentile(metric, wm, count, p,    idx) {
        idx = int((count - 1) * p + 0.999999) + 1
        if (idx < 1) idx = 1
        if (idx > count) idx = count
        return metric[wm, idx]
    }
    function delta(a, b) {
        if (a == 0) return "n/a"
        return sprintf("%+.1f%%", (b - a) / a * 100)
    }
    END {
        if (wm_count != 2) {
            print "error: expected 2 different WMs"
            exit 1
        }
        wm1 = order[1]
        wm2 = order[2]
        sort_metric(visible, wm1, n[wm1])
        sort_metric(visible, wm2, n[wm2])
        sort_metric(focus, wm1, focus_n[wm1])
        sort_metric(focus, wm2, focus_n[wm2])

        printf "%-28s %12s %12s %10s\n", "metric", wm1, wm2, "delta"
        printf "%-28s %12s %12s %10s\n", "------", "------", "------", "-----"
        printf "%-28s %12s %12s %10s\n", "ok samples", result_count[wm1, "ok"] "/" n[wm1], result_count[wm2, "ok"] "/" n[wm2], ""
        v1 = percentile(visible, wm1, n[wm1], 0.50); v2 = percentile(visible, wm2, n[wm2], 0.50)
        printf "%-28s %12.1f %12.1f %10s\n", "visible p50 ms", v1, v2, delta(v1, v2)
        v1 = percentile(visible, wm1, n[wm1], 0.95); v2 = percentile(visible, wm2, n[wm2], 0.95)
        printf "%-28s %12.1f %12.1f %10s\n", "visible p95 ms", v1, v2, delta(v1, v2)
        v1 = percentile(visible, wm1, n[wm1], 0.99); v2 = percentile(visible, wm2, n[wm2], 0.99)
        printf "%-28s %12.1f %12.1f %10s\n", "visible p99 ms", v1, v2, delta(v1, v2)
        v1 = visible_sum[wm1] / n[wm1]; v2 = visible_sum[wm2] / n[wm2]
        printf "%-28s %12.1f %12.1f %10s\n", "visible mean ms", v1, v2, delta(v1, v2)
        printf "%-28s %12d %12d %10s\n", "focus samples", focus_n[wm1], focus_n[wm2], ""
        if (focus_n[wm1] == n[wm1] && focus_n[wm2] == n[wm2]) {
            v1 = percentile(focus, wm1, focus_n[wm1], 0.50); v2 = percentile(focus, wm2, focus_n[wm2], 0.50)
            printf "%-28s %12.1f %12.1f %10s\n", "focus p50 ms", v1, v2, delta(v1, v2)
            v1 = percentile(focus, wm1, focus_n[wm1], 0.95); v2 = percentile(focus, wm2, focus_n[wm2], 0.95)
            printf "%-28s %12.1f %12.1f %10s\n", "focus p95 ms", v1, v2, delta(v1, v2)
            v1 = percentile(focus, wm1, focus_n[wm1], 0.99); v2 = percentile(focus, wm2, focus_n[wm2], 0.99)
            printf "%-28s %12.1f %12.1f %10s\n", "focus p99 ms", v1, v2, delta(v1, v2)
            v1 = focus_sum[wm1] / focus_n[wm1]; v2 = focus_sum[wm2] / focus_n[wm2]
            printf "%-28s %12.1f %12.1f %10s\n", "focus mean ms", v1, v2, delta(v1, v2)
        }
    }' "$file1" "$file2"
}

summarize_parket_trace() {
    local trace="$1"
    [[ -f "$trace" ]] || return 0
    awk '
    index($0, "\"name\":\"workspace_switch\"") {
        if (number_value($0, "ax_writes") == 0 && number_value($0, "target_workspace") == number_value($0, "active_workspace")) {
            next
        }
        n++
        duration[n] = number_value($0, "duration_ms")
        hide[n] = number_value($0, "hide_ms")
        retile[n] = number_value($0, "retile_ms")
        focus[n] = number_value($0, "focus_ms")
        queue[n] = number_value($0, "queue_delay_ms")
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
            print "parket_internal samples=0"
            exit
        }
        sort_numbers(duration, n)
        sort_numbers(queue, n)
        sort_numbers(hide, n)
        sort_numbers(retile, n)
        sort_numbers(focus, n)
        printf "parket_internal duration_p95=%.1f queue_p95=%.1f hide_p95=%.1f retile_p95=%.1f focus_p95=%.1f samples=%d\n", \
            percentile(duration, n, 0.95), percentile(queue, n, 0.95), percentile(hide, n, 0.95), percentile(retile, n, 0.95), percentile(focus, n, 0.95), n
    }' "$trace"
}

run_window_manager() {
    local wm="$1"
    require_accessibility

    if [[ "$wm" == "parket" && -n "$(pgrep -x AeroSpace 2>/dev/null || true)" ]]; then
        die "AeroSpace must be stopped before measuring parket"
    fi
    if [[ "$wm" == "aerospace" && -n "$(pgrep -x parket 2>/dev/null || true)" ]]; then
        die "parket must be stopped before measuring AeroSpace"
    fi
    if [[ "$wm" == "parket" && -n "$(pgrep -x parket 2>/dev/null || true)" ]]; then
        die "parket must be stopped before latency-compare parket"
    fi

    make build
    local bundle executable timestamp map external_trace parket_trace tmp_home
    bundle=$(bash scripts/build-fixture-app.sh)
    executable="$bundle/Contents/MacOS/ParketHarnessApp"
    timestamp=$(date +%Y-%m-%d-%H%M%S)
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/parket-latency.XXXXXX")
    tmp_home="$tmp_dir/home"
    map="$tmp_dir/workspace-map.tsv"
    external_trace="latency-${wm}-${SCENARIO_LABEL}-${timestamp}.jsonl"
    parket_trace="perf-workspace-switch-${timestamp}.jsonl"
    display_multiplier=1
    if [[ "$DISTRIBUTE_SCREENS" == "1" ]]; then
        display_multiplier=$(screen_count)
    fi
    fixture_moving_window_count=0
    SETUP_WINDOWS_PER_WORKSPACE=$((WINDOWS_PER_WORKSPACE * display_multiplier))
    window_count=$((WORKSPACE_COUNT * SETUP_WINDOWS_PER_WORKSPACE))
    expected_standard_count=$((window_count * APP_INSTANCES))
    expected_titles_per_workspace=$((SETUP_WINDOWS_PER_WORKSPACE * APP_INSTANCES))
    if [[ "$NATIVE_TABS" == "1" ]]; then
        expected_standard_count=$((expected_standard_count * 2))
        expected_titles_per_workspace=$((expected_titles_per_workspace * 2))
    fi
    mkdir -p "$tmp_home"
    : > "$external_trace"
    if [[ "$TRACE_PARKET" == "1" ]]; then
        : > "$parket_trace"
    fi

    fixture_pids=()
    aerospace_pid=""
    AEROSPACE_STARTED=0
    pkill -x ParketHarnessApp 2>/dev/null || true
    sleep 1

    if [[ "$wm" == "aerospace" ]]; then
        start_aerospace_if_needed "$tmp_home"
    fi

    start_fixture "$executable"

    if [[ "$wm" == "parket" ]]; then
        if [[ "$TRACE_PARKET" == "1" ]]; then
            HOME="$tmp_home" PARKET_TRACE_PATH="$parket_trace" PARKET_MANAGED_BUNDLE_ID=com.parket.harness .build/release/parket &
        else
            HOME="$tmp_home" PARKET_MANAGED_BUNDLE_ID=com.parket.harness .build/release/parket &
        fi
        parket_pid=$!
    else
        parket_pid=""
    fi

    cleanup() {
        [[ -n "${parket_pid:-}" ]] && kill "$parket_pid" 2>/dev/null || true
        if [[ "${AEROSPACE_STARTED:-0}" == "1" && -n "${aerospace_pid:-}" ]]; then
            kill "$aerospace_pid" 2>/dev/null || true
        fi
        for pid in "${fixture_pids[@]:-}"; do
            kill "$pid" 2>/dev/null || true
        done
        pkill -x ParketHarnessApp 2>/dev/null || true
        rm -rf "$tmp_dir"
    }
    trap cleanup EXIT

    wait_for_perf_fixture || die "fixture did not become ready"
    sleep 2
    [[ -n "$parket_pid" ]] && kill -0 "$parket_pid"

    prepare_workspace_switch
    capture_map "$map"
    run_warmup_cycle "$wm" "$map"
    if [[ "$TRACE_PARKET" == "1" ]]; then
        : > "$parket_trace"
    fi
    run_external_cycle "$wm" "$map" "$external_trace" "$ROUNDS"

    echo "scenario: $SCENARIO_LABEL"
    echo "external_trace: $external_trace"
    summarize_latency_file "$external_trace"
    require_all_ok_samples "$external_trace"
    if [[ "$wm" == "parket" && "$TRACE_PARKET" == "1" ]]; then
        echo "parket_trace: $parket_trace"
        summarize_parket_trace "$parket_trace"
    fi
}

run_matrix_case() {
    local label="$1"
    shift
    echo "latency-compare matrix: $label parket"
    if ! bash "$0" parket --label "$label" "$@"; then
        echo "latency-compare matrix: $label parket failed"
        return 1
    fi
    local parket_file
    parket_file=$(ls -t "latency-parket-$label-"*.jsonl | head -n 1)

    echo "latency-compare matrix: $label aerospace"
    if ! bash "$0" aerospace --label "$label" "$@"; then
        echo "latency-compare matrix: $label aerospace failed correctness; latency comparison skipped"
        return 0
    fi
    local aerospace_file
    aerospace_file=$(ls -t "latency-aerospace-$label-"*.jsonl | head -n 1)

    bash "$0" compare "$parket_file" "$aerospace_file"
}

run_matrix() {
    run_matrix_case default --rounds 20 --workspaces 9 --windows-per-workspace 3 --delay-ms 10
    run_matrix_case large-9x8 --rounds 8 --workspaces 9 --windows-per-workspace 8 --delay-ms 10
    run_matrix_case multi-app --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --app-instances 2
    run_matrix_case native-tabs --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --native-tabs
    echo "latency-compare matrix: churn skipped, target window identity is intentionally unstable"
    echo "latency-compare matrix: focus-thrash skipped, focus identity is intentionally unstable"
    if [[ "$(screen_count)" -gt 1 ]]; then
        run_matrix_case multi-monitor --rounds 8 --workspaces 9 --windows-per-workspace 3 --delay-ms 10 --distribute-screens
    else
        echo "latency-compare matrix: multi-monitor skipped, only one display is available"
    fi
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage
shift

case "$cmd" in
    parket|aerospace)
        parse_common_options "$@"
        run_window_manager "$cmd"
        ;;
    compare)
        [[ $# -lt 2 ]] && usage
        compare_latency_files "$1" "$2"
        ;;
    matrix)
        parse_common_options "$@"
        run_matrix
        ;;
    *)
        usage
        ;;
esac
