# tatami

minimal tiling window manager for macOS. emulates workspaces by moving windows offscreen - no private API, no SIP modifications. inspired by [dwm](https://dwm.suckless.org/) and [AeroSpace](https://github.com/nikitabobko/AeroSpace).

swift, zero dependencies.

## features

- **workspaces** - 9 virtual workspaces via offscreen window hiding
- **master-stack tiling** - new windows auto-tile in dwm-style layout
- **monocle layout** - per-workspace fullscreen mode, toggle with option+m
- **menubar indicator** - badge widgets show active workspace and occupied ones
- **custom keybindings** - bind any key combo to shell commands, compile-time config
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

custom bindings are defined in `Config.swift` - see configuration below.

## configuration

like dwm's `config.def.h` / `config.h`. defaults live in `Sources/Config.def.swift` (tracked in git). on first build, it is copied to `Sources/Config.swift` (gitignored) - your local config.

edit `Sources/Config.swift` and rebuild:

```swift
enum Config {
    static let workspaceCount = 9
    static let masterRatio: CGFloat = 0.55
    static let modifier: CGEventFlags = .maskAlternate

    static let customBindings: [Binding] = [
        Binding(key: Key.return, shift: true, command: "open -n -a Terminal"),
        Binding(key: Key.b, shift: true, command: "open -n -a Safari"),
    ]
}
```

`Key` enum provides named constants for all common key codes (`Key.return`, `Key.space`, `Key.a`-`Key.z`, etc). custom bindings always require `Config.modifier` (alt by default); the `shift` parameter adds shift to the combo.

## requirements

- macOS 14+, Apple Silicon
- accessibility permission
- input monitoring permission

## install

```bash
brew tap basuev/tatami
brew install --cask tatami
```

or build from source:

```bash
make install
open /Applications/tatami.app
```

grant permissions in system settings -> privacy & security when prompted, then relaunch.

## update

```bash
brew upgrade --cask tatami
```

or from source:

```bash
make install
```

replaces only the binary - permissions persist.

## uninstall

```bash
brew uninstall --cask tatami
```

or:

```bash
make uninstall
```

## comparison

|  | tatami | [AeroSpace](https://github.com/nikitabobko/AeroSpace) | [yabai](https://github.com/koekeishiya/yabai) | [Amethyst](https://github.com/ianyh/Amethyst) |
|--|--------|-----------|-------|----------|
| language | swift | swift | c / obj-c | swift |
| dependencies | 0 | 4 | 1 (skhd) | 1+ |
| private API | no | yes (1) | yes (many) | no |
| SIP disabled | no | no | optional | no |
| auto-tiling | yes | yes | yes | yes |
| virtual workspaces | yes | yes | yes | yes |
| config | compile-time | toml | cli | gui + yaml |
| layouts | master-stack, monocle | tree (i3) | bsp | 14+ |
| lines of code | ~1k | ~15k | ~20k | ~15k |

tatami is not trying to compete with these projects. it exists for those who want the absolute minimum: a single layout, a few keybindings, zero dependencies, and code small enough to read in one sitting.

## license

MIT
