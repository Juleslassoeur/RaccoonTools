import Foundation

struct ToolCommand: Identifiable {
    let id = UUID()
    let path: [String]           // e.g. ["get", "sound", "youtube"]
    let description: String
    let parameterName: String?   // e.g. "url", nil if no param needed
    let usesLLM: Bool
    let handler: (String) async throws -> String

    init(path: [String], description: String, parameterName: String? = nil,
         usesLLM: Bool = false, handler: @escaping (String) async throws -> String) {
        self.path = path
        self.description = description
        self.parameterName = parameterName
        self.usesLLM = usesLLM
        self.handler = handler
    }

    var fullPath: String { path.joined(separator: " ") }
}

class ToolRegistry: ObservableObject {
    static let shared = ToolRegistry()

    @Published var tools: [ToolCommand] = []

    func register(_ tool: ToolCommand) {
        tools.append(tool)
    }

    /// Returns tools whose path starts with the given tokens (prefix match)
    func search(tokens: [String]) -> [ToolCommand] {
        if tokens.isEmpty { return tools }
        return tools.filter { tool in
            for (i, token) in tokens.enumerated() {
                if i >= tool.path.count { return false }
                let t = token.lowercased()
                let p = tool.path[i].lowercased()
                if i == tokens.count - 1 {
                    // Last token: prefix match (for typing in progress)
                    if !p.hasPrefix(t) { return false }
                } else {
                    // Earlier tokens: exact match
                    if p != t { return false }
                }
            }
            return true
        }
    }

    /// Returns the best autocomplete suggestion for current input
    func autocompleteSuggestion(for input: String) -> String? {
        let tokens = tokenize(input)
        let matches = search(tokens: tokens)
        guard let best = matches.first else { return nil }

        // Build the completed path up to the next level
        let currentDepth = tokens.count
        if currentDepth <= best.path.count {
            let completed = best.path.prefix(currentDepth).joined(separator: " ")
            if completed.lowercased() != input.trimmingCharacters(in: .whitespaces).lowercased() {
                return completed
            }
            // Current input already matches — suggest next level
            if currentDepth < best.path.count {
                return best.path.prefix(currentDepth + 1).joined(separator: " ")
            }
            // Full match — show param hint
            if let param = best.parameterName {
                return best.fullPath + " [\(param)]"
            }
        }
        return nil
    }

    /// Try to find an exact tool match, returning (tool, remaining param string)
    func resolve(input: String) -> (ToolCommand, String)? {
        let tokens = tokenize(input)
        // Try longest match first
        for length in stride(from: tokens.count, through: 1, by: -1) {
            let pathTokens = Array(tokens.prefix(length))
            let match = tools.first { tool in
                tool.path.count == length && zip(tool.path, pathTokens).allSatisfy {
                    $0.0.lowercased() == $0.1.lowercased()
                }
            }
            if let match {
                let param = tokens.dropFirst(length).joined(separator: " ")
                return (match, param)
            }
        }
        return nil
    }

    /// Returns the unique next-level segments for tree-style navigation.
    /// e.g. tokens=[] → ["get", "history"], tokens=["get"] → ["youtube","transcript","txt"]
    func nextSegments(for tokens: [String]) -> [SegmentSuggestion] {
        let matches = search(tokens: tokens)
        let depth = tokens.count
        var seen = Set<String>()
        var results: [SegmentSuggestion] = []

        for tool in matches {
            guard depth < tool.path.count else { continue }
            let segment = tool.path[depth]
            guard seen.insert(segment).inserted else { continue }

            let isLeaf = tool.path.count == depth + 1
            let children = matches.filter { $0.path.count > depth && $0.path[depth] == segment }
            let childCount = children.count
            let anyLLM = children.contains { $0.usesLLM }
            let desc = isLeaf ? tool.description : "\(childCount) tool\(childCount > 1 ? "s" : "")"
            let usesLLM = isLeaf ? tool.usesLLM : anyLLM
            results.append(SegmentSuggestion(segment: segment, description: desc, isLeaf: isLeaf, tool: isLeaf ? tool : nil, usesLLM: usesLLM))
        }
        // Sort: folders first, then alphabetical
        return results.sorted { a, b in
            if a.isLeaf != b.isLeaf { return !a.isLeaf } // folders first
            return a.segment.lowercased() < b.segment.lowercased()
        }
    }

    /// Build tree structure for menu bar grouping
    func buildTree() -> [ToolTreeNode] {
        var root: [ToolTreeNode] = []
        for tool in tools {
            insertIntoTree(node: &root, tool: tool, depth: 0)
        }
        return sortTree(root)
    }

    private func sortTree(_ nodes: [ToolTreeNode]) -> [ToolTreeNode] {
        nodes.map { node in
            var n = node
            n.children = sortTree(n.children)
            return n
        }.sorted { a, b in
            let aIsFolder = !a.children.isEmpty
            let bIsFolder = !b.children.isEmpty
            if aIsFolder != bIsFolder { return aIsFolder }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    private func insertIntoTree(node: inout [ToolTreeNode], tool: ToolCommand, depth: Int) {
        guard depth < tool.path.count else { return }
        let segment = tool.path[depth]

        if let idx = node.firstIndex(where: { $0.name == segment }) {
            if depth == tool.path.count - 1 {
                node[idx].tool = tool
            } else {
                insertIntoTree(node: &node[idx].children, tool: tool, depth: depth + 1)
            }
        } else {
            var newNode = ToolTreeNode(
                name: segment,
                children: [],
                tool: depth == tool.path.count - 1 ? tool : nil
            )
            if depth < tool.path.count - 1 {
                insertIntoTree(node: &newNode.children, tool: tool, depth: depth + 1)
            }
            node.append(newNode)
        }
    }

    func tokenize(_ input: String) -> [String] {
        input.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map(String.init)
    }

    /// Check if all current tokens are exact complete matches (not partial)
    func allTokensComplete(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let matches = search(tokens: tokens)
        guard !matches.isEmpty else { return false }
        // Check if the last token exactly matches the path component of every match at that depth
        let depth = tokens.count - 1
        return matches.allSatisfy { tool in
            depth < tool.path.count && tool.path[depth].lowercased() == tokens[depth].lowercased()
        }
    }
}

struct SegmentSuggestion: Identifiable {
    let id = UUID()
    let segment: String
    let description: String
    let isLeaf: Bool
    let tool: ToolCommand?
    let usesLLM: Bool
}

struct ToolTreeNode: Identifiable {
    let id = UUID()
    let name: String
    var children: [ToolTreeNode]
    var tool: ToolCommand?
}

/// Parses user input into structured command state
struct CommandState {
    let tokens: [String]
    let matchedTool: ToolCommand?
    let parameter: String
    let suggestions: [ToolCommand]

    init(input: String, registry: ToolRegistry) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        self.tokens = registry.tokenize(trimmed)

        if let (tool, param) = registry.resolve(input: trimmed) {
            self.matchedTool = tool
            self.parameter = param
            self.suggestions = [tool]
        } else {
            self.matchedTool = nil
            self.parameter = ""
            self.suggestions = registry.search(tokens: tokens)
        }
    }
}
