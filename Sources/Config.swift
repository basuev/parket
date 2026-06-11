import Cocoa

package enum HotkeyModifier: String, Equatable {
    case option
    case control
    case command
}

package struct Binding {
    let key: UInt16
    let shift: Bool
    let command: String

    init(key: UInt16, shift: Bool = false, command: String) {
        self.key = key
        self.shift = shift
        self.command = command
    }
}

package enum Key {
    static let `return`: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51

    static let a: UInt16 = 0
    static let b: UInt16 = 11
    static let c: UInt16 = 8
    static let d: UInt16 = 2
    static let e: UInt16 = 14
    static let f: UInt16 = 3
    static let g: UInt16 = 5
    static let h: UInt16 = 4
    static let i: UInt16 = 34
    static let j: UInt16 = 38
    static let k: UInt16 = 40
    static let l: UInt16 = 37
    static let m: UInt16 = 46
    static let n: UInt16 = 45
    static let o: UInt16 = 31
    static let p: UInt16 = 35
    static let q: UInt16 = 12
    static let r: UInt16 = 15
    static let s: UInt16 = 1
    static let t: UInt16 = 17
    static let u: UInt16 = 32
    static let v: UInt16 = 9
    static let w: UInt16 = 13
    static let x: UInt16 = 7
    static let y: UInt16 = 16
    static let z: UInt16 = 6

    static let zero: UInt16 = 29
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let five: UInt16 = 23
    static let six: UInt16 = 22
    static let seven: UInt16 = 26
    static let eight: UInt16 = 28
    static let nine: UInt16 = 25

    static let minus: UInt16 = 27
    static let equal: UInt16 = 24
    static let leftBracket: UInt16 = 33
    static let rightBracket: UInt16 = 30
    static let semicolon: UInt16 = 41
    static let quote: UInt16 = 39
    static let comma: UInt16 = 43
    static let period: UInt16 = 47
    static let slash: UInt16 = 44
    static let backslash: UInt16 = 42
    static let grave: UInt16 = 50

    static let byName: [String: UInt16] = [
        "return": Key.return, "tab": Key.tab, "space": Key.space,
        "escape": Key.escape, "delete": Key.delete,
        "a": Key.a, "b": Key.b, "c": Key.c, "d": Key.d, "e": Key.e,
        "f": Key.f, "g": Key.g, "h": Key.h, "i": Key.i, "j": Key.j,
        "k": Key.k, "l": Key.l, "m": Key.m, "n": Key.n, "o": Key.o,
        "p": Key.p, "q": Key.q, "r": Key.r, "s": Key.s, "t": Key.t,
        "u": Key.u, "v": Key.v, "w": Key.w, "x": Key.x, "y": Key.y,
        "z": Key.z,
        "0": Key.zero, "1": Key.one, "2": Key.two, "3": Key.three,
        "4": Key.four, "5": Key.five, "6": Key.six, "7": Key.seven,
        "8": Key.eight, "9": Key.nine,
        "minus": Key.minus, "equal": Key.equal,
        "leftbracket": Key.leftBracket, "rightbracket": Key.rightBracket,
        "semicolon": Key.semicolon, "quote": Key.quote,
        "comma": Key.comma, "period": Key.period,
        "slash": Key.slash, "backslash": Key.backslash, "grave": Key.grave,
    ]

    static let namesByCode: [UInt16: String] = [
        Key.return: "return", Key.tab: "tab", Key.space: "space",
        Key.escape: "escape", Key.delete: "delete",
        Key.a: "a", Key.b: "b", Key.c: "c", Key.d: "d", Key.e: "e",
        Key.f: "f", Key.g: "g", Key.h: "h", Key.i: "i", Key.j: "j",
        Key.k: "k", Key.l: "l", Key.m: "m", Key.n: "n", Key.o: "o",
        Key.p: "p", Key.q: "q", Key.r: "r", Key.s: "s", Key.t: "t",
        Key.u: "u", Key.v: "v", Key.w: "w", Key.x: "x", Key.y: "y",
        Key.z: "z",
        Key.zero: "0", Key.one: "1", Key.two: "2", Key.three: "3",
        Key.four: "4", Key.five: "5", Key.six: "6", Key.seven: "7",
        Key.eight: "8", Key.nine: "9",
        Key.minus: "minus", Key.equal: "equal",
        Key.leftBracket: "leftbracket", Key.rightBracket: "rightbracket",
        Key.semicolon: "semicolon", Key.quote: "quote",
        Key.comma: "comma", Key.period: "period",
        Key.slash: "slash", Key.backslash: "backslash", Key.grave: "grave",
    ]

    static let numberKeys: [UInt16] = [
        Key.one, Key.two, Key.three, Key.four, Key.five,
        Key.six, Key.seven, Key.eight, Key.nine,
    ]

    static func name(for code: UInt16) -> String {
        namesByCode[code] ?? "keycode_\(code)"
    }
}

package struct BuiltinBindings {
    var focusNext: (key: UInt16, shift: Bool) = (Key.j, false)
    var focusPrev: (key: UInt16, shift: Bool) = (Key.k, false)
    var swapMaster: (key: UInt16, shift: Bool) = (Key.return, false)
    var toggleLayout: (key: UInt16, shift: Bool) = (Key.m, false)
    var focusMonitorPrev: (key: UInt16, shift: Bool) = (Key.comma, false)
    var focusMonitorNext: (key: UInt16, shift: Bool) = (Key.period, false)
    var moveMonitorPrev: (key: UInt16, shift: Bool) = (Key.comma, true)
    var moveMonitorNext: (key: UInt16, shift: Bool) = (Key.period, true)
    var lastWorkspace: (key: UInt16, shift: Bool) = (Key.tab, false)
}

package struct Config {
    package static let defaultWorkspaceCount = 9
    package static let defaultMasterRatio: CGFloat = 0.55
    @MainActor
    package static var shared = Config()
    package static var path: String {
        NSString("~/.config/parket/config.toml").expandingTildeInPath
    }
    package static var url: URL {
        URL(fileURLWithPath: path)
    }

    package var workspaceCount: Int = defaultWorkspaceCount
    package var masterRatio: CGFloat = defaultMasterRatio
    package var modifier: HotkeyModifier = .option
    package var customBindings: [Binding] = [
        Binding(key: Key.return, shift: true, command: "open -n -a Terminal")
    ]
    package var bindings = BuiltinBindings()

    package private(set) var numberKeys: [UInt16: Int] = buildNumberKeys(count: defaultWorkspaceCount)

    private static func buildNumberKeys(count: Int) -> [UInt16: Int] {
        var map: [UInt16: Int] = [:]
        for i in 0..<count { map[Key.numberKeys[i]] = i + 1 }
        return map
    }

    @MainActor
    package static func load() {
        guard FileManager.default.fileExists(atPath: path) else { return }

        guard let data = FileManager.default.contents(atPath: path),
            let text = String(data: data, encoding: .utf8)
        else {
            fputs("parket: failed to read config file\n", stderr)
            return
        }

        guard let config = parse(text, report: { fputs("parket: \($0)\n", stderr) }) else { return }
        shared = config
    }

    package static func parse(_ text: String, report: (String) -> Void = { _ in }) -> Config? {
        let toml: [String: Any]
        do {
            toml = try Toml.parse(text)
        } catch {
            report("config parse error: \(error)")
            return nil
        }

        var config = Config()

        if let count = toml["workspace_count"] as? Int, WorkspaceBounds.isValidCount(count) {
            config.workspaceCount = count
            config.numberKeys = buildNumberKeys(count: count)
        }

        if let ratio = toml["master_ratio"] as? Double, ratio > 0, ratio < 1 {
            config.masterRatio = CGFloat(ratio)
        }

        if let mod = toml["modifier"] as? String {
            switch mod {
            case "option": config.modifier = .option
            case "control": config.modifier = .control
            case "command": config.modifier = .command
            default: report("unknown modifier '\(mod)', using option")
            }
        }

        if let bindings = toml["bindings"] as? [String: Any] {
            applyBinding(bindings, "focus_next", to: &config.bindings.focusNext, report: report)
            applyBinding(bindings, "focus_prev", to: &config.bindings.focusPrev, report: report)
            applyBinding(bindings, "swap_master", to: &config.bindings.swapMaster, report: report)
            applyBinding(bindings, "toggle_layout", to: &config.bindings.toggleLayout, report: report)
            applyBinding(bindings, "focus_monitor_prev", to: &config.bindings.focusMonitorPrev, report: report)
            applyBinding(bindings, "focus_monitor_next", to: &config.bindings.focusMonitorNext, report: report)
            applyBinding(bindings, "move_monitor_prev", to: &config.bindings.moveMonitorPrev, report: report)
            applyBinding(bindings, "move_monitor_next", to: &config.bindings.moveMonitorNext, report: report)
            applyBinding(bindings, "last_workspace", to: &config.bindings.lastWorkspace, report: report)
        }

        if let customs = toml["custom"] as? [[String: Any]] {
            config.customBindings = customs.compactMap { entry in
                guard let keyStr = entry["key"] as? String,
                    let command = entry["command"] as? String
                else { return nil }
                let (keyCode, shift) = parseKeyString(keyStr)
                guard let code = keyCode else {
                    report("unknown key '\(keyStr)' in custom binding")
                    return nil
                }
                return Binding(key: code, shift: shift, command: command)
            }
        }

        return config
    }

    @MainActor
    package static func openConfig() {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !manager.fileExists(atPath: path) {
            try? defaultConfigText.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private static func parseKeyString(_ s: String) -> (key: UInt16?, shift: Bool) {
        if s.hasPrefix("shift+") {
            let name = String(s.dropFirst(6))
            return (Key.byName[name], true)
        }
        return (Key.byName[s], false)
    }

    private static func applyBinding(
        _ dict: [String: Any], _ name: String,
        to binding: inout (key: UInt16, shift: Bool),
        report: (String) -> Void
    ) {
        guard let value = dict[name] as? String else { return }
        let (keyCode, shift) = parseKeyString(value)
        guard let code = keyCode else {
            report("unknown key '\(value)' for binding '\(name)'")
            return
        }
        binding = (code, shift)
    }

    private static var defaultConfigText: String {
        """
        workspace_count = 9
        master_ratio = 0.55
        modifier = "option"

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
        """
    }
}
