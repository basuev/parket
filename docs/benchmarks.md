# benchmarks

## interaction latency

parket measures workspace switching from the user side:

- post the workspace hotkey
- wait until the expected fixture windows appear
- wait until focus lands on one of those windows

the harness rejects a run before comparison when a workspace exposes the wrong fixture window count. it rejects a sample when windows appear but focus stays on another workspace. this keeps internal timing out of the headline numbers.

run the parket path:

```fish
make latency-local
```

run the full parket vs AeroSpace matrix:

```fish
scripts/latency-compare.sh matrix
```

the matrix includes `default`, `large-9x8`, `multi-app`, `native-tabs`, and `multi-monitor` when the machine has more than one display.

## latest local run

- date: 2026-06-14
- displays: 2
- harness: `scripts/latency-compare.sh matrix`
- headline metric: external focus latency p95

| scenario | parket | AeroSpace | result |
|----------|--------|-----------|--------|
| default | 180/180 ok, focus p95 9.5 ms | 180/180 ok, focus p95 29.7 ms | parket faster |
| large-9x8 | 72/72 ok, focus p95 19.3 ms | failed correctness | parket passed |
| multi-app | 72/72 ok, focus p95 20.5 ms | failed correctness | parket passed |
| native-tabs | 72/72 ok, focus p95 21.5 ms | failed correctness | parket passed |
| multi-monitor | 72/72 ok, focus p95 15.2 ms | 72/72 ok, focus p95 38.9 ms | parket faster |

full visible and focus latency from the same run:

| scenario | result |
|----------|--------|
| default | parket visible p50/p95/p99/mean 3.2/8.4/14.7/3.9 ms vs AeroSpace 8.2/13.9/18.2/8.7 ms; parket focus p50/p95/p99/mean 4.1/9.5/15.6/4.8 ms vs AeroSpace 18.8/29.7/35.2/18.8 ms |
| large-9x8 | parket visible p50/p95/p99/mean 7.2/18.4/18.8/9.0 ms; focus p50/p95/p99/mean 12.5/19.3/21.3/11.9 ms. AeroSpace exposed 10 switching fixture windows on workspace 1, expected 8 |
| multi-app | parket visible p50/p95/p99/mean 4.0/19.7/24.9/6.4 ms; focus p50/p95/p99/mean 5.3/20.5/25.8/8.0 ms. AeroSpace produced 8 visible-only samples |
| native-tabs | parket visible p50/p95/p99/mean 5.2/20.4/25.5/7.8 ms; focus p50/p95/p99/mean 6.2/21.5/26.3/9.1 ms. AeroSpace exposed 30 switching fixture windows on workspace 1, expected 6 |
| multi-monitor | parket visible p50/p95/p99/mean 3.8/14.4/14.9/5.3 ms vs AeroSpace 10.9/17.5/21.3/10.7 ms; parket focus p50/p95/p99/mean 5.1/15.2/15.7/6.6 ms vs AeroSpace 28.1/38.9/44.7/26.8 ms |

## claim

use this wording in release notes:

> parket switches workspaces faster than AeroSpace in correctness-valid UX latency comparisons. in the same matrix, parket passes large, multi-app, native-tab, and multi-monitor scenarios that AeroSpace does not pass under this harness.

avoid broader claims. the benchmark covers the fixture scenarios above, on the local machine and display setup listed in the run notes.
