import Foundation

package enum Toml {
    package enum Error: Swift.Error, CustomStringConvertible {
        case parse(line: Int, message: String)
        package var description: String {
            switch self {
            case .parse(let line, let message): return "line \(line): \(message)"
            }
        }
    }

    package static func parse(_ text: String) throws -> [String: Any] {
        var root: [String: Any] = [:]
        var currentTable: String?
        var currentArrayTable: String?

        for (lineNumber, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.prefix(while: { $0 != "#" })
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]") {
                let name = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { throw Error.parse(line: lineNumber + 1, message: "empty table name") }
                currentArrayTable = name
                currentTable = nil
                if root[name] == nil { root[name] = [[String: Any]]() }
                guard root[name] is [[String: Any]] else {
                    throw Error.parse(line: lineNumber + 1, message: "'\(name)' is not an array of tables")
                }
                var arr = root[name] as! [[String: Any]]
                arr.append([:])
                root[name] = arr
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let name = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { throw Error.parse(line: lineNumber + 1, message: "empty table name") }
                currentTable = name
                currentArrayTable = nil
                if root[name] == nil { root[name] = [String: Any]() }
                guard root[name] is [String: Any] else {
                    throw Error.parse(line: lineNumber + 1, message: "'\(name)' is not a table")
                }
                continue
            }

            guard let eqIndex = trimmed.firstIndex(of: "=") else {
                throw Error.parse(line: lineNumber + 1, message: "expected key = value")
            }

            let key = trimmed[trimmed.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
            let valStr = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { throw Error.parse(line: lineNumber + 1, message: "empty key") }
            guard !valStr.isEmpty else { throw Error.parse(line: lineNumber + 1, message: "empty value") }
            let value = try parseValue(valStr, line: lineNumber + 1)

            if let arrayTable = currentArrayTable {
                var arr = root[arrayTable] as! [[String: Any]]
                arr[arr.count - 1][key] = value
                root[arrayTable] = arr
            } else if let table = currentTable {
                var dict = root[table] as! [String: Any]
                dict[key] = value
                root[table] = dict
            } else {
                root[key] = value
            }
        }

        return root
    }

    private static func parseValue(_ s: String, line: Int) throws -> Any {
        if s.hasPrefix("\"") {
            guard s.count >= 2, s.hasSuffix("\"") else {
                throw Error.parse(line: line, message: "unterminated string")
            }
            return String(s.dropFirst().dropLast())
        }
        if s == "true" { return true }
        if s == "false" { return false }
        if s.contains(".") {
            guard let d = Double(s) else { throw Error.parse(line: line, message: "invalid float '\(s)'") }
            return d
        }
        guard let i = Int(s) else { throw Error.parse(line: line, message: "invalid value '\(s)'") }
        return i
    }
}
