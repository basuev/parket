# Benchmarks

## Interaction Latency

The parket harness measures workspace switching from the user side:

- Post the workspace hotkey.
- Wait until the expected fixture windows appear.
- Wait until focus lands on one of those windows.

The harness rejects a run before comparison when a workspace exposes the wrong fixture window count. It rejects a sample when windows appear but focus stays on another workspace. This keeps internal timing out of the headline numbers.

Run the parket path:

```fish
make latency-local
```

Run the full parket vs AeroSpace matrix:

```fish
scripts/latency-compare.sh matrix
```

The matrix includes `default`, `large-9x8`, `multi-app`, `native-tabs`, and `multi-monitor` when the machine has more than one display.

## Latest Local Run

- Date: 2026-06-14
- Displays: 2
- Harness: `scripts/latency-compare.sh matrix`
- Headline metric: external focus latency p95

| Scenario | parket | AeroSpace | Result |
|----------|--------|-----------|--------|
| default | 180/180 ok, focus p95 9.5 ms | 180/180 ok, focus p95 29.7 ms | parket faster |
| large-9x8 | 72/72 ok, focus p95 19.3 ms | failed correctness | parket passed |
| multi-app | 72/72 ok, focus p95 20.5 ms | failed correctness | parket passed |
| native-tabs | 72/72 ok, focus p95 21.5 ms | failed correctness | parket passed |
| multi-monitor | 72/72 ok, focus p95 15.2 ms | 72/72 ok, focus p95 38.9 ms | parket faster |

Full visible and focus latency from the same run:

| Scenario | Result |
|----------|--------|
| default | parket visible p50/p95/p99/mean 3.2/8.4/14.7/3.9 ms vs AeroSpace 8.2/13.9/18.2/8.7 ms; parket focus p50/p95/p99/mean 4.1/9.5/15.6/4.8 ms vs AeroSpace 18.8/29.7/35.2/18.8 ms |
| large-9x8 | parket visible p50/p95/p99/mean 7.2/18.4/18.8/9.0 ms; focus p50/p95/p99/mean 12.5/19.3/21.3/11.9 ms. AeroSpace exposed 10 switching fixture windows on workspace 1, expected 8 |
| multi-app | parket visible p50/p95/p99/mean 4.0/19.7/24.9/6.4 ms; focus p50/p95/p99/mean 5.3/20.5/25.8/8.0 ms. AeroSpace produced 8 visible-only samples |
| native-tabs | parket visible p50/p95/p99/mean 5.2/20.4/25.5/7.8 ms; focus p50/p95/p99/mean 6.2/21.5/26.3/9.1 ms. AeroSpace exposed 30 switching fixture windows on workspace 1, expected 6 |
| multi-monitor | parket visible p50/p95/p99/mean 3.8/14.4/14.9/5.3 ms vs AeroSpace 10.9/17.5/21.3/10.7 ms; parket focus p50/p95/p99/mean 5.1/15.2/15.7/6.6 ms vs AeroSpace 28.1/38.9/44.7/26.8 ms |

## Claim

Use this wording in release notes:

> The parket workspace switch path is faster than AeroSpace in correctness-valid UX latency comparisons. In the same matrix, parket passes large, multi-app, native-tab, and multi-monitor scenarios that AeroSpace does not pass under this harness.

Avoid broader claims. The benchmark covers the fixture scenarios above, on the local machine and display setup listed in the run notes.
