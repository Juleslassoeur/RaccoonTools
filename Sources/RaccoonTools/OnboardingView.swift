import SwiftUI
import AppKit

/// First-launch onboarding: 3 small steps — Accessibility permission,
/// API key, and a "try it" example with the configured hotkey.
struct OnboardingView: View {
    var onFinish: () -> Void

    @ObservedObject var settings = SettingsManager.shared
    @State private var step = 0
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var selectedProviderID: String = ""
    @State private var apiKey: String = ""
    @State private var keySaved = false

    private let accessibilityTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch step {
                case 0: accessibilityStep
                case 1: apiKeyStep
                default: tryItStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(24)

            Divider()

            // Footer
            HStack {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                Spacer()

                // Step dots
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                if step < 2 {
                    Button("Continue") {
                        if step == 1 { saveAPIKeyIfNeeded() }
                        step += 1
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { finish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 360)
        .onAppear {
            if selectedProviderID.isEmpty {
                selectedProviderID = settings.providers.first(where: { $0.type != .ollama })?.id
                    ?? settings.providers.first?.id ?? ""
            }
        }
        .onReceive(accessibilityTimer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    // MARK: - Step 1: Accessibility

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(icon: "hand.raised.fill",
                       title: "Accessibility Permission",
                       subtitle: "Raccoon Tools reads your selected text and pastes edits back in place. macOS requires the Accessibility permission for this.")

            HStack(spacing: 8) {
                Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(accessibilityGranted ? .green : .orange)
                Text(accessibilityGranted ? "Permission granted" : "Permission not granted yet")
                    .font(.callout)
                    .foregroundColor(accessibilityGranted ? .green : .orange)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((accessibilityGranted ? Color.green : Color.orange).opacity(0.08))
            .cornerRadius(8)

            if !accessibilityGranted {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("Enable Raccoon Tools in Privacy & Security → Accessibility, then come back here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Step 2: API key

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(icon: "key.fill",
                       title: "Connect an LLM",
                       subtitle: "Pick a provider and paste your API key. It is stored securely in the macOS Keychain — after app updates, macOS may ask to allow access again: choose \"Always Allow\".")

            Picker("Provider", selection: $selectedProviderID) {
                ForEach(settings.providers) { provider in
                    Text("\(provider.name) (\(provider.type.displayName))").tag(provider.id)
                }
            }

            HStack {
                SecureField("Paste your API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveAPIKeyIfNeeded() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if keySaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").foregroundColor(.green).font(.caption)
                    Text("Key saved").font(.caption).foregroundColor(.green)
                }
            }

            Text("No key? Skip this step — you can use Ollama locally (no key needed) or add a key later in Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Step 3: Try it

    private var tryItStep: some View {
        let hotkey = KeyComboFormatter.string(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
        return VStack(alignment: .leading, spacing: 14) {
            stepHeader(icon: "sparkles",
                       title: "Try It",
                       subtitle: "Raccoon Tools works anywhere you can select text.")

            HStack {
                Spacer()
                Text(hotkey)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                exampleRow(number: "1", text: "Select a sentence in any app — Mail, Notes, your browser...")
                exampleRow(number: "2", text: "Press \(hotkey)")
                exampleRow(number: "3", text: "Type \"make it shorter\" and hit Return to apply the edit in place")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.05))
            .cornerRadius(8)

            Text("You can also type tool commands like \"fix orth\" or \"translate\" directly.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.title3.bold())
            }
            Text(subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exampleRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveAPIKeyIfNeeded() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              let idx = settings.providers.firstIndex(where: { $0.id == selectedProviderID }) else { return }
        settings.providers[idx].apiKey = key
        keySaved = true
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }
}
