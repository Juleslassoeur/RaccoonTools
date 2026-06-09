import Foundation
import Testing
@testable import RaccoonTools

/// Thread-safe line accumulator for the @Sendable onLine callback
private final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [String] = []

    func add(_ line: String) {
        lock.lock()
        collected.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}

@Suite struct ShellExecStreamingTests {

    @Test func onLineReceivesLinesAndReturnValueKeepsFullOutput() async throws {
        let sink = LineSink()
        let output = try await shellExec(
            "/bin/sh", args: ["-c", "printf 'one\\ntwo\\rthree\\n'"],
            onLine: { sink.add($0) }
        )
        // Full output is returned unchanged (including the \r progress separator)
        #expect(output == "one\ntwo\rthree\n")
        // Lines are split on both \n and \r
        #expect(sink.lines == ["one", "two", "three"])
    }

    @Test func onLineReceivesStderrToo() async throws {
        let sink = LineSink()
        let output = try await shellExec(
            "/bin/sh", args: ["-c", "echo out; echo err >&2"],
            onLine: { sink.add($0) }
        )
        #expect(output == "out\n")
        #expect(Set(sink.lines) == ["out", "err"])
    }

    @Test func streamingModeKeepsErrorSemantics() async throws {
        let sink = LineSink()
        let output = try await shellExec(
            "/bin/sh", args: ["-c", "echo oops >&2; exit 3"],
            onLine: { sink.add($0) }
        )
        #expect(output == "Error (exit 3): oops\n")
        #expect(sink.lines == ["oops"])
    }

    @Test func withoutOnLineBehaviorIsUnchanged() async throws {
        let output = try await shellExec("/bin/echo", args: ["hi"])
        #expect(output == "hi\n")
    }
}
