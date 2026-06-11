# Parket Harness App

`ParketHarnessApp` is a local AX smoke fixture. It creates standard windows, multiple windows from one process, a minimized window, a utility panel, and a native-tab-like pair.

Build it with:

```fish
make fixture-app
```

Run the local smoke scaffold with:

```fish
make smoke-local
```

The smoke path is intentionally separate from `make check` because it needs Accessibility and a foreground macOS GUI session.
