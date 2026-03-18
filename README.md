# parket

minimal tiling window manager for macOS. emulates workspaces by moving windows offscreen - no private API, no SIP modifications. inspired by [dwm](https://dwm.suckless.org/) and [AeroSpace](https://github.com/nikitabobko/AeroSpace).

swift, zero dependencies.

## features

- **workspaces** - 9 virtual workspaces via offscreen window hiding
- **master-stack tiling** - new windows auto-tile in dwm-style layout
- **monocle layout** - per-workspace fullscreen mode, toggle with option+m
- **menubar indicator** - badge widgets show active workspace and occupied ones
- **custom keybindings** - bind any key combo to shell commands via toml config
- **multi-monitor** - per-display workspaces, each monitor has its own workspace set
- **crash safety** - all windows restore on exit

## keybindings

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

all keybindings are configurable - see configuration below.

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

custom bindings always include the modifier key (option by default). prefix with `shift+` to add shift to the combo.

to reload config at runtime, use the "Reload Config" option in the menubar menu.

## requirements

- macOS 14+, Apple Silicon
- accessibility permission
- input monitoring permission

## install

```bash
brew tap basuev/parket
brew install --cask parket
```

or build from source:

```bash
make install
open /Applications/parket.app
```

grant permissions in system settings -> privacy & security when prompted, then relaunch.

## update

```bash
brew upgrade --cask parket
```

or from source:

```bash
make install
```

replaces only the binary - permissions persist.

## uninstall

```bash
brew uninstall --cask parket
```

or:

```bash
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
| lines of code | ~1k | ~15k | ~20k | ~15k |

parket is not trying to compete with these projects. it exists for those who want the absolute minimum: a single layout, a few keybindings, zero dependencies, and code small enough to read in one sitting.

## resource usage

parket is designed to stay out of your way. here is how it compares to AeroSpace under identical conditions (Apple Silicon, macOS 26, 6 tiled windows, continuous open/close workload):

- **2x less memory** - 41 MB vs 83 MB
- **near-zero CPU** - 0.0% even during active window management, vs 2% for AeroSpace
- **40x fewer context switches** - less work for the kernel, less energy spent

fewer threads, fewer wakeups, longer battery life. you won't find parket in Activity Monitor unless you go looking for it.

<sub>measured with `scripts/benchmark.sh`. run it yourself - numbers are reproducible.</sub>

## license

MIT
