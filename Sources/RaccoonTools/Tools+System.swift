import Foundation
import AppKit

func registerSystemTools(registry: ToolRegistry, settings: SettingsManager) {
    // ============================================================
    // MARK: - WIFI
    // ============================================================

    registry.register(ToolCommand(
        path: ["wifi"],
        description: "Show current WiFi name and password",
        parameterName: nil,
        handler: { _ in
            // Get current WiFi SSID
            let ssidResult = try await shellExec("/usr/sbin/networksetup", args: ["-getairportnetwork", "en0"])
            let ssidLine = ssidResult.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIdx = ssidLine.range(of: ": ") else {
                return "Error: not connected to WiFi"
            }
            let ssid = String(ssidLine[colonIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ssid.isEmpty && !ssid.contains("not associated") else {
                return "Error: not connected to WiFi"
            }

            // Get password (will trigger macOS auth prompt)
            let passResult = try? await shellExec("/usr/bin/security", args: [
                "find-generic-password", "-wa", ssid, "-D", "AirPort network password"
            ])
            let password = passResult?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(access denied)"

            return "Network: \(ssid)\nPassword: \(password)"
        }
    ))

    // ============================================================
    // MARK: - COLOR PICKER
    // ============================================================

    registry.register(ToolCommand(
        path: ["color"],
        description: "Pick colors + auto palette generator",
        parameterName: nil,
        usesLLM: true,
        handler: { _ in "__COLOR_PICKER__" }
    ))

    // ============================================================
    // MARK: - CHAT
    // ============================================================

    registry.register(ToolCommand(
        path: ["chat"],
        description: "Free chat with LLM",
        parameterName: nil,
        usesLLM: true,
        handler: { _ in "__CHAT__" }
    ))

    // ============================================================
    // MARK: - PROMPT (two-step: content + instructions)
    // ============================================================

    registry.register(ToolCommand(
        path: ["prompt"],
        description: "Give content + instructions, LLM refines via Q&A",
        parameterName: nil,
        usesLLM: true,
        handler: { _ in "__PROMPT__" }
    ))

    // ============================================================
    // MARK: - GOOGLE
    // ============================================================

    registry.register(ToolCommand(
        path: ["google"],
        description: "Search Google for text or clipboard",
        parameterName: "query",
        handler: { input in
            var query = input.trimmingCharacters(in: .whitespaces)
            if query.isEmpty { query = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !query.isEmpty else { return "Error: no query provided and clipboard is empty" }
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = "https://www.google.com/search?q=\(encoded)"
            NSWorkspace.shared.open(URL(string: url)!)
            return "Opened Google search for: \(query)"
        }
    ))

    // ============================================================
    // MARK: - MEET
    // ============================================================

    registry.register(ToolCommand(
        path: ["meet"],
        description: "Create a new Google Meet link",
        parameterName: nil,
        handler: { _ in
            let url = "https://meet.google.com/new"
            NSWorkspace.shared.open(URL(string: url)!)
            return "Opening Google Meet — the link will be in your browser URL bar"
        }
    ))

    // ============================================================
    // MARK: - HISTORY
    // ============================================================

    registry.register(ToolCommand(
        path: ["history"],
        description: "Browse clipboard history",
        parameterName: nil,
        handler: { _ in "__HISTORY__" }
    ))
}
