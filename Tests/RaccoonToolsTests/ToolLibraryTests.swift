import Testing
@testable import RaccoonTools

struct SrtToMarkdownTests {
    @Test func convertsCuesToTimestampedLines() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello there

        2
        00:01:23,450 --> 00:01:25,000
        Second line
        continued
        """
        let md = srtToMarkdown(srt)
        #expect(md == "**[00:01]** Hello there\n\n**[01:23]** Second line continued")
    }

    @Test func keepsHoursWhenNonZero() {
        let srt = """
        1
        01:02:03,000 --> 01:02:05,000
        Late content
        """
        #expect(srtToMarkdown(srt) == "**[01:02:03]** Late content")
    }

    @Test func emptyOrGarbageYieldsEmpty() {
        #expect(srtToMarkdown("") == "")
        #expect(srtToMarkdown("not an srt at all") == "")
    }
}

struct DisabledToolsTests {
    private func makeRegistry() -> ToolRegistry {
        let registry = ToolRegistry()
        registry.register(ToolCommand(path: ["translate"], description: "t") { _ in "" })
        registry.register(ToolCommand(path: ["fix", "grammar"], description: "g") { _ in "" })
        registry.register(ToolCommand(path: ["fix", "orth"], description: "o") { _ in "" })
        return registry
    }

    @Test func disabledToolsAreExcludedFromSearchAndResolve() {
        let registry = makeRegistry()
        registry.disabledPaths = ["fix grammar"]

        let results = registry.search(tokens: ["fix"])
        #expect(results.map(\.fullPath) == ["fix orth"])
        #expect(registry.resolve(input: "fix grammar hello") == nil)
        #expect(registry.resolve(input: "fix orth hello") != nil)
    }

    @Test func disabledFolderChildHidesFromSegments() {
        let registry = makeRegistry()
        registry.disabledPaths = ["fix grammar", "fix orth"]
        // The whole "fix" folder vanishes once all children are hidden
        let segments = registry.nextSegments(for: [])
        #expect(segments.map(\.segment) == ["translate"])
    }

    @Test func emptyDisabledSetChangesNothing() {
        let registry = makeRegistry()
        #expect(registry.search(tokens: []).count == 3)
        #expect(registry.resolve(input: "fix grammar x") != nil)
    }

    @Test func pathOverridesRenameAndMoveTools() {
        let registry = makeRegistry()
        registry.markBuiltinsRegistered()
        registry.applyPathOverrides(["fix grammar": "polish text"])

        // Reachable under the new name only, with its stable identity intact
        let resolved = registry.resolve(input: "polish text hello")
        #expect(resolved?.0.bindingKey == "fix grammar")
        #expect(resolved?.1 == "hello")
        #expect(registry.resolve(input: "fix grammar hello") == nil)

        // The tree follows the new paths
        #expect(registry.nextSegments(for: ["polish"]).map(\.segment) == ["text"])
    }

    @Test func hiddenStateSurvivesRenames() {
        let registry = makeRegistry()
        registry.markBuiltinsRegistered()
        registry.applyPathOverrides(["fix grammar": "polish text"])
        registry.disabledPaths = ["fix grammar"]  // keyed by stable identity
        #expect(registry.resolve(input: "polish text hello") == nil)
    }

    @Test func emptyOverridePathIsIgnored() {
        let registry = makeRegistry()
        registry.markBuiltinsRegistered()
        registry.applyPathOverrides(["fix grammar": "   "])
        #expect(registry.resolve(input: "fix grammar hello") != nil)
    }
}
