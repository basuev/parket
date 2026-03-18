#!/usr/bin/env bash
set -euo pipefail

IDLE_DURATION=30
ACTIVE_DURATION=60
SAMPLE_INTERVAL=2
WARMUP=5
WINDOW_COUNT=6

usage() {
    echo "usage: $0 run [--duration N] [--windows N]"
    echo "       $0 compare <file1.csv> <file2.csv>"
    exit 1
}

die() { echo "error: $1" >&2; exit 1; }
warn() { echo "warning: $1" >&2; }

detect_wm() {
    local parket_pid aerospace_pid
    parket_pid=$(pgrep -x parket 2>/dev/null || true)
    aerospace_pid=$(pgrep -x AeroSpace 2>/dev/null || true)

    if [[ -n "$parket_pid" && -n "$aerospace_pid" ]]; then
        die "both parket and aerospace are running. stop one first"
    fi
    if [[ -z "$parket_pid" && -z "$aerospace_pid" ]]; then
        die "neither parket nor aerospace is running"
    fi

    if [[ -n "$parket_pid" ]]; then
        WM_NAME="parket"
        WM_PID="$parket_pid"
    else
        WM_NAME="aerospace"
        WM_PID="$aerospace_pid"
    fi
}

check_pid() {
    kill -0 "$WM_PID" 2>/dev/null || die "$WM_NAME (pid $WM_PID) died during benchmark"
}

sample() {
    local phase="$1"
    check_pid

    local rss threads cpu csw ts win_count
    ts=$(date +%s)
    rss=$(ps -o rss= -p "$WM_PID" | tr -d ' ')
    threads=$(ps -M -o pid= -p "$WM_PID" | wc -l | tr -d ' ')
    win_count=$(osascript -e 'tell application "Terminal" to count windows' 2>/dev/null || echo 0)

    local top_line
    top_line=$(top -l 2 -pid "$WM_PID" -stats pid,cpu,csw 2>/dev/null | tail -1)
    cpu=$(echo "$top_line" | awk '{gsub(/[^0-9.]/, "", $2); print $2}')
    csw=$(echo "$top_line" | awk '{gsub(/[^0-9.]/, "", $3); print $3}')

    [[ -z "$cpu" ]] && cpu="0"
    [[ -z "$csw" ]] && csw="0"

    echo "$ts,$WM_NAME,$phase,$rss,$cpu,$threads,$csw,$win_count"
    echo "$ts,$WM_NAME,$phase,$rss,$cpu,$threads,$csw,$win_count" >> "$OUTPUT"
}

open_windows() {
    local n="$1"
    for _ in $(seq 1 "$n"); do
        osascript -e 'tell application "Terminal" to do script ""' >/dev/null 2>&1
        sleep 0.5
    done
}

close_all_terminal() {
    osascript -e 'tell application "Terminal" to close every window' 2>/dev/null || true
    sleep 1
}

workload_loop() {
    while true; do
        osascript -e 'tell application "Terminal" to do script ""' >/dev/null 2>&1
        sleep 2
        osascript -e 'tell application "Terminal" to close front window' 2>/dev/null || true
        sleep 1
    done
}

write_header() {
    {
        echo "# benchmark: $WM_NAME"
        echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "# hardware: $(sysctl -n hw.model 2>/dev/null || echo unknown)"
        echo "# cpu: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
        echo "# ram: $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB"
        echo "# macos: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
        echo "# monitors: $(system_profiler SPDisplaysDataType 2>/dev/null | grep -c Resolution || echo unknown)"
        echo "# load: $(sysctl -n vm.loadavg 2>/dev/null || echo unknown)"
        echo "# idle_duration: $IDLE_DURATION"
        echo "# active_duration: $ACTIVE_DURATION"
        echo "# windows: $WINDOW_COUNT"
        echo "timestamp,wm,phase,rss_kb,cpu_pct,threads,csw,windows"
    } > "$OUTPUT"
}

print_summary() {
    echo ""
    echo "--- summary: $WM_NAME ---"
    echo ""
    awk -F',' '
    /^#/ || /^timestamp/ { next }
    {
        phase = $3
        n = ++count[phase]
        rss[phase, n] = $4 + 0
        cpu[phase, n] = $5 + 0
        threads[phase, n] = $6 + 0
        csw_val = $7 + 0
        gsub(/[^0-9.]/, "", csw_val)
        csw[phase, n] = csw_val + 0
        wins[phase, n] = $8 + 0
        rss_sum[phase] += $4
        cpu_sum[phase] += $5
        threads_sum[phase] += $6
        csw_sum[phase] += csw_val
        wins_sum[phase] += $8
    }
    function sort_arr(arr, phase, n,    i, j, tmp) {
        for (i = 2; i <= n; i++) {
            tmp = arr[phase, i]
            j = i - 1
            while (j >= 1 && arr[phase, j] > tmp) {
                arr[phase, j+1] = arr[phase, j]
                j--
            }
            arr[phase, j+1] = tmp
        }
    }
    function pct(arr, phase, n, p,    idx) {
        idx = int(n * p / 100 + 0.5)
        if (idx < 1) idx = 1
        if (idx > n) idx = n
        return arr[phase, idx]
    }
    END {
        phases[1] = "idle"; phases[2] = "active"
        for (p = 1; p <= 2; p++) {
            phase = phases[p]
            n = count[phase]
            if (n == 0) continue
            sort_arr(rss, phase, n)
            sort_arr(cpu, phase, n)
            sort_arr(threads, phase, n)
            sort_arr(csw, phase, n)
            sort_arr(wins, phase, n)
            printf "%s phase (%d samples):\n", phase, n
            printf "  %-20s %10s %10s %10s %10s\n", "metric", "mean", "min", "max", "p95"
            printf "  %-20s %10.0f %10.0f %10.0f %10.0f\n", "rss (KB)", \
                rss_sum[phase]/n, pct(rss, phase, n, 0), pct(rss, phase, n, 100), pct(rss, phase, n, 95)
            printf "  %-20s %10.1f %10.1f %10.1f %10.1f\n", "cpu (%)", \
                cpu_sum[phase]/n, pct(cpu, phase, n, 0), pct(cpu, phase, n, 100), pct(cpu, phase, n, 95)
            printf "  %-20s %10.0f %10.0f %10.0f %10.0f\n", "threads", \
                threads_sum[phase]/n, pct(threads, phase, n, 0), pct(threads, phase, n, 100), pct(threads, phase, n, 95)
            printf "  %-20s %10.0f %10.0f %10.0f %10.0f\n", "ctx switches", \
                csw_sum[phase]/n, pct(csw, phase, n, 0), pct(csw, phase, n, 100), pct(csw, phase, n, 95)
            printf "  %-20s %10.0f %10.0f %10.0f %10.0f\n", "windows", \
                wins_sum[phase]/n, pct(wins, phase, n, 0), pct(wins, phase, n, 100), pct(wins, phase, n, 95)
            printf "\n"
        }
    }' "$OUTPUT"

    echo "results saved to $OUTPUT"
}

run_benchmark() {
    detect_wm

    local datestamp
    datestamp=$(date +%Y-%m-%d-%H%M%S)
    OUTPUT="benchmark-${WM_NAME}-${datestamp}.csv"

    echo "benchmarking $WM_NAME (pid $WM_PID)"
    echo "output: $OUTPUT"

    write_header

    echo ""
    echo "closing existing terminal windows..."
    close_all_terminal

    echo "opening $WINDOW_COUNT windows..."
    open_windows "$WINDOW_COUNT"

    echo "warming up ${WARMUP}s..."
    sleep "$WARMUP"

    echo ""
    echo "--- idle phase (${IDLE_DURATION}s) ---"
    local elapsed=0
    while (( elapsed < IDLE_DURATION )); do
        sample "idle"
        (( elapsed += SAMPLE_INTERVAL ))
    done

    echo ""
    echo "--- active phase (${ACTIVE_DURATION}s) ---"
    workload_loop &
    local workload_pid=$!

    elapsed=0
    while (( elapsed < ACTIVE_DURATION )); do
        sample "active"
        (( elapsed += SAMPLE_INTERVAL ))
    done

    kill "$workload_pid" 2>/dev/null || true
    wait "$workload_pid" 2>/dev/null || true

    echo ""
    echo "cleaning up..."
    close_all_terminal

    print_summary
}

compare() {
    local file1="$1" file2="$2"
    [[ -f "$file1" ]] || die "file not found: $file1"
    [[ -f "$file2" ]] || die "file not found: $file2"

    echo "comparing: $file1 vs $file2"
    echo ""

    awk -F',' '
    /^#/ || /^timestamp/ { next }
    {
        key = $2 SUBSEP $3
        if (!seen_wm[$2]++) wm_order[++wm_count] = $2
        count[key]++
        rss_sum[key] += $4
        cpu_sum[key] += $5
        threads_sum[key] += $6
        csw_sum[key] += $7
        wins_sum[key] += $8
    }
    function delta(a, b) {
        if (a == 0) return "n/a"
        return sprintf("%+.1f%%", (b - a) / a * 100)
    }
    END {
        if (wm_count != 2) {
            print "error: expected 2 different WMs in input files"
            exit 1
        }
        wm1 = wm_order[1]
        wm2 = wm_order[2]

        phases[1] = "idle"
        phases[2] = "active"

        printf "%-25s %12s %12s %10s\n", "metric", wm1, wm2, "delta"
        printf "%-25s %12s %12s %10s\n", "------", "------", "------", "-----"

        for (p = 1; p <= 2; p++) {
            phase = phases[p]
            k1 = wm1 SUBSEP phase
            k2 = wm2 SUBSEP phase
            n1 = count[k1]; n2 = count[k2]
            if (n1 == 0 || n2 == 0) continue

            r1 = rss_sum[k1]/n1; r2 = rss_sum[k2]/n2
            c1 = cpu_sum[k1]/n1; c2 = cpu_sum[k2]/n2
            t1 = threads_sum[k1]/n1; t2 = threads_sum[k2]/n2
            s1 = csw_sum[k1]/n1; s2 = csw_sum[k2]/n2
            w1 = wins_sum[k1]/n1; w2 = wins_sum[k2]/n2

            printf "%-25s %12.0f %12.0f %10s\n", phase " rss (KB)", r1, r2, delta(r1, r2)
            printf "%-25s %12.1f %12.1f %10s\n", phase " cpu (%)", c1, c2, delta(c1, c2)
            printf "%-25s %12.0f %12.0f %10s\n", phase " threads", t1, t2, delta(t1, t2)
            printf "%-25s %12.0f %12.0f %10s\n", phase " ctx switches", s1, s2, delta(s1, s2)
            printf "%-25s %12.0f %12.0f %10s\n", phase " windows", w1, w2, delta(w1, w2)
        }
    }' "$file1" "$file2"
}

# --- main ---

[[ $# -lt 1 ]] && usage

cmd="$1"; shift

case "$cmd" in
    run)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --duration) ACTIVE_DURATION="$2"; shift 2 ;;
                --windows)  WINDOW_COUNT="$2"; shift 2 ;;
                *) die "unknown option: $1" ;;
            esac
        done
        run_benchmark
        ;;
    compare)
        [[ $# -lt 2 ]] && usage
        compare "$1" "$2"
        ;;
    *)
        usage
        ;;
esac
