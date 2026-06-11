import Testing

@testable import ParketCore

@Suite("TOML")
struct TomlTests {
    @Test func parsesScalarsAndTables() throws {
        let parsed = try Toml.parse(
            """
            workspace_count = 4
            master_ratio = 0.6
            modifier = "control"

            [bindings]
            focus_next = "j"
            enabled = true
            """
        )

        #expect(parsed["workspace_count"] as? Int == 4)
        #expect(parsed["master_ratio"] as? Double == 0.6)
        #expect(parsed["modifier"] as? String == "control")
        let bindings = try #require(parsed["bindings"] as? [String: Any])
        #expect(bindings["focus_next"] as? String == "j")
        #expect(bindings["enabled"] as? Bool == true)
    }

    @Test func parsesArrayTables() throws {
        let parsed = try Toml.parse(
            """
            [[custom]]
            key = "shift+return"
            command = "open -n -a Terminal"

            [[custom]]
            key = "space"
            command = "echo ok"
            """
        )

        let custom = try #require(parsed["custom"] as? [[String: Any]])
        #expect(custom.count == 2)
        #expect(custom[0]["key"] as? String == "shift+return")
        #expect(custom[1]["command"] as? String == "echo ok")
    }

    @Test func rejectsMissingEquals() {
        #expect(throws: Toml.Error.self) {
            try Toml.parse("workspace_count 4")
        }
    }

    @Test func rejectsUnterminatedString() {
        #expect(throws: Toml.Error.self) {
            try Toml.parse("modifier = \"option")
        }
    }
}
