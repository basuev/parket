import Testing

@testable import ParketCore

@Suite("Runtime version diagnostics")
struct RuntimeVersionTests {
    @Test func reportsBundleVersionAndBuild() {
        let version = RuntimeVersion(info: [
            "CFBundleShortVersionString": "0.8.1",
            "CFBundleVersion": "42",
        ])

        #expect(
            version.diagnosticLines == [
                "parket_version: 0.8.1",
                "parket_build: 42",
            ])
    }

    @Test func reportsUnknownWhenBundleMetadataIsMissing() {
        let version = RuntimeVersion(info: [:])

        #expect(
            version.diagnosticLines == [
                "parket_version: unknown",
                "parket_build: unknown",
            ])
    }
}
