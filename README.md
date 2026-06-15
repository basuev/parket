# parket

A small native tiling window manager for macOS.

It tiles normal document windows with a dwm-style master-stack layout and emulates workspaces by moving inactive workspace windows offscreen. It uses Swift, public macOS APIs, and zero runtime dependencies. It does not require SIP changes.

![parket preview](assets/parket-preview.png)

Inspired by [dwm](https://dwm.suckless.org/) and [AeroSpace](https://github.com/nikitabobko/AeroSpace).

## Install

```fish
brew install --cask basuev/parket/parket
```

Open parket from Applications. On first launch, parket opens the Accessibility prompt. Grant access, then choose Recheck in the permission window or Recheck Accessibility from the menubar.

Homebrew is the normal install path. Release zips use ad-hoc signing.

## Requirements

- macOS 14+
- Apple Silicon
- Accessibility permission

## Keys

| Key | Action |
|-----|--------|
| `Option + 1-9` | Switch workspace |
| `Option + Shift + 1-9` | Move focused window to workspace |
| `Option + J/K` | Focus next or previous window |
| `Option + Return` | Swap focused window with master |
| `Option + Tab` | Switch to last active workspace |
| `Option + M` | Toggle monocle layout |
| `Option + ,` / `Option + .` | Focus previous or next monitor |
| `Option + Shift + ,` / `Option + Shift + .` | Move window to previous or next monitor |

Command+Tab remains the macOS app switcher. If it selects a window on another parket workspace, parket opens that workspace and focuses the selected window.

Menubar commands: Pause Tiling, Retile Now, Pause and Restore Windows, Open Config, Copy Diagnostic Report, Reload Config.

## Model

- 9 workspaces per display.
- Master-stack and monocle layouts.
- One native tab group counts as one tileable window.
- Panels, dialogs, minimized windows, fullscreen windows, and dead AX elements stay out of workspace state.
- Recovery actions bring tracked windows back onscreen.

## Configuration

Edit `~/.config/parket/config.toml`. All fields are optional.

```toml
workspace_count = 9
master_ratio = 0.55
modifier = "option"

[bindings]
focus_next = "j"
focus_prev = "k"
swap_master = "return"
toggle_layout = "m"
last_workspace = "tab"

[[custom]]
key = "shift+return"
command = "open -n -a Terminal"
```

Bindings use the configured modifier key. Prefix a key with `shift+` to add Shift. See [config.example.toml](config.example.toml) for supported key names and defaults.

Use Reload Config from the menubar after editing.

## Build from Source

```fish
make install
open /Applications/parket.app
```

Run the required local gate:

```fish
make check
```

`make check` runs formatting, policy checks, tests, and a release build. See [Tests/Smoke/README.md](Tests/Smoke/README.md) for AX smoke checks and [docs/benchmarks.md](docs/benchmarks.md) for latency runs.

## Update

```fish
brew update
brew upgrade --cask basuev/parket/parket
```

Source install:

```fish
git pull
make install
```

Source installs replace only `Contents/MacOS/parket`, so Accessibility permission survives the update.

## Uninstall

```fish
brew uninstall --cask basuev/parket/parket
rm -rf /Applications/parket.app
```

Source checkout:

```fish
make uninstall
```

## Benchmarks

The latency harness measures hotkey dispatch to the expected visible, focused fixture window.

Latest local two-display matrix, 2026-06-14:

| Scenario | parket | AeroSpace |
|----------|--------|-----------|
| Default focus p95 | 9.5 ms | 29.7 ms |
| Multi-monitor focus p95 | 15.2 ms | 38.9 ms |
| Native-tabs scenario | Passed | Failed correctness |

See [docs/benchmarks.md](docs/benchmarks.md) for the full matrix, run notes, and claim wording.

## Contributing

Use issues for reproducible bugs, app compatibility reports, and scoped feature proposals. Good reports include macOS version, install method, affected apps, steps to reproduce, and the diagnostic report when relevant.

PRs should be small, pass `make check`, and preserve the project constraints: public macOS APIs, no runtime dependencies, small native code, recoverable window movement.

## License

MIT
