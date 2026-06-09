import Foundation
import Testing
@testable import RaccoonTools

@Suite struct FrecencyTests {

    private func entry(_ toolPath: String) -> HistoryEntry {
        HistoryEntry(command: toolPath, toolPath: toolPath, result: "ok")
    }

    // MARK: - Score weighting by age

    @Test func entryWeightsDependOnAge() {
        let e = entry("translate")
        let created = e.date

        // < 1h → 100
        #expect(HistoryManager.frecencyScores(for: [e], now: created.addingTimeInterval(60))["translate"] == 100)
        #expect(HistoryManager.frecencyScores(for: [e], now: created.addingTimeInterval(3599))["translate"] == 100)
        // < 24h → 80
        #expect(HistoryManager.frecencyScores(for: [e], now: created.addingTimeInterval(3601))["translate"] == 80)
        #expect(HistoryManager.frecencyScores(for: [e], now: created.addingTimeInterval(23 * 3600))["translate"] == 80)
        // < 7d → 30
        #expect(HistoryManager.frecencyScores(for: [e], now: created.addingTimeInterval(2 * 86_400))["translate"] == 30)
        // older → 10
        #expect(HistoryManager.frecencyScores(for: [e], now: created.addingTimeInterval(8 * 86_400))["translate"] == 10)
    }

    @Test func scoresSumAcrossEntriesPerToolPath() {
        let a1 = entry("translate")
        let a2 = entry("translate")
        let b = entry("fix grammar")
        let now = a1.date.addingTimeInterval(60)
        let scores = HistoryManager.frecencyScores(for: [a1, a2, b], now: now)
        #expect(scores["translate"] == 200)   // two recent uses
        #expect(scores["fix grammar"] == 100) // one recent use
        #expect(scores["unknown"] == nil)
    }

    @Test func emptyHistoryGivesEmptyScores() {
        #expect(HistoryManager.frecencyScores(for: []).isEmpty)
    }

    // MARK: - Ranked suggestion ordering

    private func makeRegistry() -> ToolRegistry {
        let registry = ToolRegistry()
        let noop: (String) async throws -> String = { _ in "" }
        registry.register(ToolCommand(path: ["get", "youtube", "sound"], description: "Download audio",
                                      parameterName: "url", handler: noop))
        registry.register(ToolCommand(path: ["get", "youtube", "video"], description: "Download video",
                                      parameterName: "url", handler: noop))
        registry.register(ToolCommand(path: ["translate"], description: "Translate text",
                                      parameterName: "text", usesLLM: true, handler: noop))
        registry.register(ToolCommand(path: ["fix", "grammar"], description: "Fix grammar",
                                      parameterName: "text", usesLLM: true, handler: noop))
        registry.register(ToolCommand(path: ["fix"], description: "Fix anything",
                                      parameterName: "text", usesLLM: true, handler: noop))
        registry.register(ToolCommand(path: ["ping"], description: "Ping", handler: noop))
        return registry
    }

    @Test func leavesAreRankedByScoreDescending() {
        let registry = makeRegistry()
        // "translate" used more recently/often than "ping"
        let scores: [String: Double] = ["translate": 100, "ping": 30]
        let segments = registry.nextSegments(for: [], scores: scores)
        // Folders stay first (alphabetical between equal-score folders),
        // then leaves by score descending
        #expect(segments.map(\.segment) == ["fix", "get", "translate", "ping"])
    }

    @Test func leafLevelOrderingWithScores() {
        let registry = makeRegistry()
        let scores: [String: Double] = ["get youtube video": 80, "get youtube sound": 10]
        let segments = registry.nextSegments(for: ["get", "youtube"], scores: scores)
        #expect(segments.map(\.segment) == ["video", "sound"])
    }

    @Test func folderScoreIsMaxOfDescendants() {
        let registry = makeRegistry()
        let noop: (String) async throws -> String = { _ in "" }
        // Add a second root folder so two folders compete
        registry.register(ToolCommand(path: ["file", "compress"], description: "Compress",
                                      parameterName: "image", handler: noop))

        // "file compress" scores below one "get" descendant but above the other:
        // folder score must take the MAX, so "get" (80) outranks "file" (50)
        let scores: [String: Double] = [
            "get youtube sound": 10,
            "get youtube video": 80,
            "file compress": 50,
        ]
        let segments = registry.nextSegments(for: [], scores: scores)
        let folders = segments.filter { !$0.isLeaf }.map(\.segment)
        #expect(folders.first == "get")
        #expect(folders.contains("file"))

        let get = segments.first { $0.segment == "get" }
        #expect(get?.score == 80)
        let file = segments.first { $0.segment == "file" }
        #expect(file?.score == 50)
    }

    @Test func emptyScoresFallBackToAlphabetical() {
        let registry = makeRegistry()
        // Same expectations as the historical default-ordering test
        let segments = registry.nextSegments(for: [], scores: [:])
        #expect(segments.map(\.segment) == ["fix", "get", "ping", "translate"])
        #expect(segments.map(\.isLeaf) == [false, false, true, true])

        // And the parameterless call stays identical
        let defaultSegments = registry.nextSegments(for: [])
        #expect(defaultSegments.map(\.segment) == segments.map(\.segment))
    }

    @Test func tieBreakIsAlphabeticalAmongEqualScores() {
        let registry = makeRegistry()
        let scores: [String: Double] = ["translate": 50, "ping": 50]
        let segments = registry.nextSegments(for: [], scores: scores)
        let leaves = segments.filter(\.isLeaf).map(\.segment)
        #expect(leaves == ["ping", "translate"])
    }
}
