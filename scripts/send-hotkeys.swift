import CoreGraphics
import Darwin
import Foundation

let keyCodes: [Int: CGKeyCode] = [
    1: 18,
    2: 19,
    3: 20,
    4: 21,
    5: 23,
    6: 22,
    7: 26,
    8: 28,
    9: 25,
]

func fail(_ message: String) -> Never {
    fputs("send-hotkeys: \(message)\n", stderr)
    exit(1)
}

func value(after flag: String, default defaultValue: Int) -> Int {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
        return defaultValue
    }
    return Int(args[index + 1]) ?? defaultValue
}

func hasFlag(_ flag: String) -> Bool {
    CommandLine.arguments.contains(flag)
}

func post(number: Int, shift: Bool, delayMicroseconds: useconds_t) {
    guard let keyCode = keyCodes[number] else {
        fail("unsupported workspace \(number)")
    }

    var flags: CGEventFlags = [.maskAlternate]
    if shift {
        flags.insert(.maskShift)
    }

    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else {
        fail("could not create keyboard event")
    }

    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    usleep(2_000)
    up.post(tap: .cghidEventTap)
    usleep(delayMicroseconds)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("usage: send-hotkeys.swift setup|cycle|press [options]")
}

let mode = args[1]
let workspaceCount = min(max(value(after: "--workspaces", default: 9), 1), 9)
let workspace = min(max(value(after: "--workspace", default: 1), 1), 9)
let windowsPerWorkspace = max(value(after: "--windows-per-workspace", default: 3), 1)
let rounds = max(value(after: "--rounds", default: 20), 1)
let delayMicroseconds = useconds_t(max(value(after: "--delay-ms", default: 20), 0) * 1000)

switch mode {
case "setup":
    guard workspaceCount > 1 else { exit(0) }
    for workspace in 2...workspaceCount {
        for _ in 0..<windowsPerWorkspace {
            post(number: workspace, shift: true, delayMicroseconds: delayMicroseconds)
        }
    }
    post(number: 1, shift: false, delayMicroseconds: delayMicroseconds)
case "cycle":
    for _ in 0..<rounds {
        if workspaceCount > 1 {
            for workspace in 2...workspaceCount {
                post(number: workspace, shift: false, delayMicroseconds: delayMicroseconds)
            }
        }
        post(number: 1, shift: false, delayMicroseconds: delayMicroseconds)
    }
case "press":
    post(number: workspace, shift: hasFlag("--shift"), delayMicroseconds: delayMicroseconds)
default:
    fail("usage: send-hotkeys.swift setup|cycle|press [options]")
}
