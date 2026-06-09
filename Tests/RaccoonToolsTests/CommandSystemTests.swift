import Testing
@testable import RaccoonTools

@Suite struct CommandSystemTests {

    // Fresh registry per test — never use ToolRegistry.shared here
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

    // MARK: - tokenize

    @Test func tokenizeTrimsAndSplitsOnSpaces() {
        let registry = makeRegistry()
        #expect(registry.tokenize("  get   youtube sound  ") == ["get", "youtube", "sound"])
        #expect(registry.tokenize("") == [])
        #expect(registry.tokenize("   ") == [])
        #expect(registry.tokenize("translate") == ["translate"])
    }

    // MARK: - search

    @Test func searchEmptyTokensReturnsAllTools() {
        let registry = makeRegistry()
        #expect(registry.search(tokens: []).count == 6)
    }

    @Test func searchLastTokenIsPrefixMatch() {
        let registry = makeRegistry()
        #expect(registry.search(tokens: ["g"]).map(\.fullPath)
                == ["get youtube sound", "get youtube video"])
        #expect(registry.search(tokens: ["get", "yo"]).count == 2)
        #expect(registry.search(tokens: ["fix", "g"]).map(\.fullPath) == ["fix grammar"])
    }

    @Test func searchEarlierTokensRequireExactMatch() {
        // "ge" as a non-last token must match exactly, so nothing matches
        let registry = makeRegistry()
        #expect(registry.search(tokens: ["ge", "youtube"]).isEmpty)
    }

    @Test func searchIsCaseInsensitive() {
        let registry = makeRegistry()
        #expect(registry.search(tokens: ["GET", "YOUTUBE"]).count == 2)
    }

    @Test func searchTokensDeeperThanPathDoNotMatch() {
        let registry = makeRegistry()
        #expect(registry.search(tokens: ["translate", "extra"]).isEmpty)
    }

    // MARK: - resolve

    @Test func resolveFullPathReturnsRemainingParameter() {
        let registry = makeRegistry()
        let resolved = registry.resolve(input: "get youtube sound https://youtu.be/abc")
        #expect(resolved?.0.fullPath == "get youtube sound")
        #expect(resolved?.1 == "https://youtu.be/abc")
    }

    @Test func resolvePrefersLongestMatch() {
        let registry = makeRegistry()
        // Both ["fix"] and ["fix","grammar"] exist; longest path wins
        let long = registry.resolve(input: "fix grammar this sentence")
        #expect(long?.0.fullPath == "fix grammar")
        #expect(long?.1 == "this sentence")

        let short = registry.resolve(input: "fix something else")
        #expect(short?.0.fullPath == "fix")
        #expect(short?.1 == "something else")
    }

    @Test func resolveIsCaseInsensitive() {
        let registry = makeRegistry()
        let resolved = registry.resolve(input: "TRANSLATE Hello")
        #expect(resolved?.0.fullPath == "translate")
        #expect(resolved?.1 == "Hello")
    }

    @Test func resolveReturnsNilForPartialOrUnknownPath() {
        let registry = makeRegistry()
        #expect(registry.resolve(input: "get youtube") == nil)
        #expect(registry.resolve(input: "unknown thing") == nil)
        #expect(registry.resolve(input: "") == nil)
    }

    @Test func resolveEmptyParameterWhenNoneGiven() {
        let registry = makeRegistry()
        let resolved = registry.resolve(input: "translate")
        #expect(resolved?.0.fullPath == "translate")
        #expect(resolved?.1 == "")
    }

    // MARK: - autocompleteSuggestion

    @Test func autocompleteCompletesPartialToken() {
        let registry = makeRegistry()
        #expect(registry.autocompleteSuggestion(for: "g") == "get")
        #expect(registry.autocompleteSuggestion(for: "tra") == "translate")
    }

    @Test func autocompleteSuggestsNextLevelWhenTokenComplete() {
        let registry = makeRegistry()
        #expect(registry.autocompleteSuggestion(for: "get") == "get youtube")
        #expect(registry.autocompleteSuggestion(for: "get youtube") == "get youtube sound")
    }

    @Test func autocompleteShowsParamHintOnFullMatch() {
        let registry = makeRegistry()
        #expect(registry.autocompleteSuggestion(for: "get youtube sound") == "get youtube sound [url]")
        #expect(registry.autocompleteSuggestion(for: "translate") == "translate [text]")
    }

    @Test func autocompleteNilForNoParamFullMatchAndUnknownInput() {
        let registry = makeRegistry()
        #expect(registry.autocompleteSuggestion(for: "ping") == nil)
        #expect(registry.autocompleteSuggestion(for: "zzz") == nil)
    }

    // MARK: - nextSegments

    @Test func nextSegmentsRootLevelFoldersFirstThenAlphabetical() {
        let registry = makeRegistry()
        let segments = registry.nextSegments(for: [])
        #expect(segments.map(\.segment) == ["fix", "get", "ping", "translate"])
        #expect(segments.map(\.isLeaf) == [false, false, true, true])
    }

    @Test func nextSegmentsFolderChildCountsAndLLMFlag() {
        let registry = makeRegistry()
        let segments = registry.nextSegments(for: [])
        let fix = segments.first { $0.segment == "fix" }
        // "fix grammar" is registered before "fix", so the segment is a folder with 2 children
        #expect(fix?.description == "2 tools")
        #expect(fix?.usesLLM == true)
        #expect(fix?.tool == nil)

        let get = segments.first { $0.segment == "get" }
        #expect(get?.description == "2 tools")
        #expect(get?.usesLLM == false)
    }

    @Test func nextSegmentsLeafLevel() {
        let registry = makeRegistry()
        let segments = registry.nextSegments(for: ["get", "youtube"])
        #expect(segments.map(\.segment) == ["sound", "video"])
        #expect(segments.allSatisfy { $0.isLeaf })
        #expect(segments[0].description == "Download audio")
        #expect(segments[0].tool?.fullPath == "get youtube sound")
    }

    @Test func nextSegmentsSingularFolderLevel() {
        let registry = makeRegistry()
        let segments = registry.nextSegments(for: ["get"])
        #expect(segments.count == 1)
        #expect(segments[0].segment == "youtube")
        #expect(segments[0].isLeaf == false)
        #expect(segments[0].description == "2 tools")
    }

    // MARK: - allTokensComplete

    @Test func allTokensComplete() {
        let registry = makeRegistry()
        #expect(registry.allTokensComplete([]))
        #expect(registry.allTokensComplete(["get"]))
        #expect(registry.allTokensComplete(["get", "youtube"]))
        #expect(registry.allTokensComplete(["FIX"]))   // case-insensitive
        #expect(!registry.allTokensComplete(["ge"]))   // partial token
        #expect(!registry.allTokensComplete(["zzz"]))  // no match
    }

    // MARK: - CommandState

    @Test func commandStateMatchedInput() {
        let registry = makeRegistry()
        let state = CommandState(input: "translate hello world", registry: registry)
        #expect(state.tokens == ["translate", "hello", "world"])
        #expect(state.matchedTool?.fullPath == "translate")
        #expect(state.parameter == "hello world")
        #expect(state.suggestions.count == 1)
    }

    @Test func commandStateUnmatchedInputFallsBackToSearch() {
        let registry = makeRegistry()
        let state = CommandState(input: "get you", registry: registry)
        #expect(state.matchedTool == nil)
        #expect(state.parameter == "")
        #expect(state.suggestions.count == 2)
    }

    @Test func commandStateEmptyInputSuggestsAllTools() {
        let registry = makeRegistry()
        let state = CommandState(input: "", registry: registry)
        #expect(state.matchedTool == nil)
        #expect(state.tokens == [])
        #expect(state.suggestions.count == 6)
    }
}
