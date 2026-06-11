# parket

minimal tiling window manager for macOS.

parket uses swift and public macOS APIs. no private API, no SIP modifications, zero dependencies.

it emulates workspaces by moving windows offscreen and tiles windows with a dwm-style master-stack layout.

![parket preview](assets/parket-preview.png)

inspired by [dwm](https://dwm.suckless.org/) and [AeroSpace](https://github.com/nikitabobko/AeroSpace).

## install

```fish
brew install --cask basuev/parket/parket
```

or build from source:

```fish
make install
open /Applications/parket.app
```

parket opens a permission window on first launch. grant Accessibility, then use Recheck from the window or Recheck Accessibility from the menubar.

the GitHub release zip is ad-hoc signed for now. Homebrew is the recommended install path.

## requirements

- macOS 14+, Apple Silicon
- accessibility permission

## features

- **workspaces** - 9 virtual workspaces via offscreen window hiding
- **master-stack tiling** - new windows auto-tile in dwm-style layout
- **monocle layout** - per-workspace fullscreen mode, toggle with option+m
- **menubar indicator** - badge widgets show active workspace and occupied ones
- **custom keybindings** - bind supported key names to shell commands via toml config
- **multi-monitor** - per-display workspaces, each monitor has its own workspace set
- **app switcher follow** - command+tab to a hidden workspace window opens that workspace
- **exit safety** - tracked windows restore on quit, SIGTERM, and SIGINT
- **permission onboarding** - menubar and permission window show Accessibility state
- **escape hatches** - pause tiling, retile now, restore all windows, open config, copy diagnostics

## keybindings

macOS command+tab stays the system app switcher. when it selects a window on another parket workspace, parket opens that workspace and focuses the selected window.

| key | action |
|-----|--------|
| `Option + 1-9` | switch workspace |
| `Option + Shift + 1-9` | move focused window to workspace |
| `Option + J/K` | focus next/prev window |
| `Option + Return` | swap focused window with master |
| `Option + Tab` | switch to last active workspace |
| `Option + M` | toggle monocle layout |
| `Option + ,` / `Option + .` | focus prev/next monitor |
| `Option + Shift + ,` / `Option + Shift + .` | move window to prev/next monitor |

most action bindings are configurable - see configuration below. workspace switch and move bindings stay on 1-9.

## configuration

edit `~/.config/parket/config.toml`. all fields are optional - defaults are used for anything not specified.

```toml
workspace_count = 9
master_ratio = 0.55
modifier = "option"    # "option", "control", or "command"

[bindings]
focus_next = "j"
focus_prev = "k"
swap_master = "return"
toggle_layout = "m"
focus_monitor_prev = "comma"
focus_monitor_next = "period"
move_monitor_prev = "shift+comma"
move_monitor_next = "shift+period"
last_workspace = "tab"

[[custom]]
key = "shift+return"
command = "open -n -a Terminal"

[[custom]]
key = "shift+b"
command = "open -n -a Safari"
```

bindings use the modifier key (option by default). prefix with `shift+` to add shift to the combo. supported key names are `a-z`, `0-9`, `return`, `tab`, `space`, `escape`, `delete`, `comma`, `period`, `slash`, `backslash`, `minus`, `equal`, `grave`, `leftbracket`, `rightbracket`, `semicolon`, and `quote`.

to reload config at runtime, use the "Reload Config" option in the menubar menu.

the menubar menu also includes "Pause Tiling", "Retile Now", "Pause and Restore Windows", "Open Config", and "Copy Diagnostic Report". "Pause and Restore Windows" pauses tiling first, then brings tracked windows back onscreen.

## update

```fish
brew update
brew upgrade --cask basuev/parket/parket
```

Homebrew installs made with older cask metadata can still run the old uninstall step during their first upgrade. That may recreate `/Applications/parket.app` and require granting Accessibility again. Current cask metadata preserves the app bundle for future installs and updates.

or update from source:

```fish
git pull
make install
```

replaces only the binary - permissions persist.

## uninstall

```fish
brew uninstall --cask basuev/parket/parket
rm -rf /Applications/parket.app
```

or:

```fish
make uninstall
```

## comparison

|  | parket | [AeroSpace](https://github.com/nikitabobko/AeroSpace) | [yabai](https://github.com/koekeishiya/yabai) | [Amethyst](https://github.com/ianyh/Amethyst) |
|--|--------|-----------|-------|----------|
| language | swift | swift | c / obj-c | swift |
| dependencies | 0 | 4 | 1 (skhd) | 1+ |
| private API | no | yes (1) | yes (many) | no |
| SIP disabled | no | no | optional | no |
| auto-tiling | yes | yes | yes | yes |
| virtual workspaces | yes | yes | yes | yes |
| config | toml | toml | cli | gui + yaml |
| layouts | master-stack, monocle | tree (i3) | bsp | 14+ |
| lines of code | ~3.1k | ~15k | ~20k | ~15k |

LOC counts exclude tests. parket counts production Swift and package files.

parket is for users who want a small native macOS tiler with one primary layout, text config, no runtime dependencies, and public APIs only.

## resource usage

measure resource usage with `scripts/benchmark.sh`. Last local run:

- date: 2026-06-11 16:45-16:47 UTC
- machine: Mac15,6, Apple M3 Pro, macOS 26.4.1, 18 GB RAM, 2 monitors
- workload: 6 Terminal windows, 30s idle, 60s continuous open/close

| active phase mean | parket | AeroSpace |
|-------------------|--------|-----------|
| RSS | 46.5 MiB | 76.8 MiB |
| CPU | 0.0% | 0.9% |
| threads | 5 | 14 |
| context switches | 2,285 | 10,899 |

```fish
scripts/benchmark.sh run
```

the script samples RSS, CPU, thread count, context switches, and Terminal window count. run it once with parket and once with AeroSpace, then compare the latest CSV files:

```fish
set parket_csv (ls -t benchmark-parket-*.csv | head -n 1)
set aerospace_csv (ls -t benchmark-aerospace-*.csv | head -n 1)
scripts/benchmark.sh compare $parket_csv $aerospace_csv
```

## license

MIT
