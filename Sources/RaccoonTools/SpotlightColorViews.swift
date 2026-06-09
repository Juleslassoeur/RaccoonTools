import SwiftUI
import AppKit

// MARK: - Unified Color tool (history left, palette right)

extension SpotlightView {
    var colorView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Color")
                    .font(.caption.bold())
                Spacer()
                Button("Pick color") {
                    launchColorPicker()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if state.pickedColors.isEmpty {
                Text("Press Enter to pick a color from screen")
                    .foregroundColor(.secondary)
                    .padding(20)
            } else {
                HStack(spacing: 0) {
                    // LEFT: history
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(state.pickedColors.enumerated()), id: \.element.id) { index, color in
                                    let isSelected = index == state.colorSelectedIndex
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(nsColor: NSColor(
                                                red: CGFloat(color.r) / 255,
                                                green: CGFloat(color.g) / 255,
                                                blue: CGFloat(color.b) / 255, alpha: 1)))
                                            .frame(width: 20, height: 20)
                                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(color.hex)
                                                .font(.system(.caption, design: .monospaced))
                                                .fontWeight(.medium)
                                            Text(color.cssRGB)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button { copyToClipboard(color.hex) } label: {
                                            Image(systemName: "doc.on.doc").font(.caption2).foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .cornerRadius(4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        state.colorSelectedIndex = index
                                        generatePalette(for: color)
                                    }
                                    .id("color-\(index)")
                                }
                            }
                        }
                        .frame(width: 220)
                        .frame(maxHeight: 280)
                        .onChange(of: state.colorSelectedIndex) { idx in
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("color-\(idx)", anchor: .center)
                            }
                            // Generate palette for selected color
                            if idx < state.pickedColors.count {
                                generatePalette(for: state.pickedColors[idx])
                            }
                        }
                    }

                    Divider()

                    // RIGHT: palette
                    VStack(spacing: 0) {
                        HStack {
                            Text("Palette")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            if state.isRunning {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if state.paletteColors.isEmpty && !state.isRunning {
                            Text("Select a color")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxHeight: .infinity)
                        } else {
                            ForEach(state.paletteColors) { pc in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(nsColor: pc.color))
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))

                                    Text(pc.hex)
                                        .font(.system(.caption, design: .monospaced))

                                    Text(pc.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Button { copyToClipboard(pc.hex) } label: {
                                        Image(systemName: "doc.on.doc").font(.caption2).foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture { copyToClipboard(pc.hex) }
                            }
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    func launchColorPicker() {
        state.showColorPicker = true
        NotificationCenter.default.post(name: .hideSpotlightTemporary, object: nil)

        let sampler = NSColorSampler()
        sampler.show { selectedColor in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showSpotlight, object: nil)
                if let color = selectedColor {
                    let picked = PickedColor(nsColor: color)
                    state.pickedColors.insert(picked, at: 0)
                    if state.pickedColors.count > 30 {
                        state.pickedColors = Array(state.pickedColors.prefix(30))
                    }
                    state.colorSelectedIndex = 0
                    generatePalette(for: picked)
                }
            }
        }
    }

    private func generatePalette(for color: PickedColor) {
        let key = color.hex.uppercased()

        // Use cache if available
        if let cached = state.paletteCache[key] {
            state.paletteColors = cached
            return
        }

        state.paletteColors = []
        state.isRunning = true
        state.runningToolName = "color palette"

        Task {
            let settings = SettingsManager.shared
            let toolPath = "color palette"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            do {
                let result = try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: color.hex)
                await MainActor.run {
                    state.isRunning = false
                    let colors = parsePaletteColors(result, fallbackHex: color.hex)
                    state.paletteColors = colors
                    state.cachePalette(colors, for: key)
                }
            } catch {
                await MainActor.run { state.isRunning = false }
            }
        }
    }

    private func parsePaletteColors(_ text: String, fallbackHex: String) -> [PaletteColor] {
        var colors = [PaletteColor]()
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Try pipe format: #XXXXXX|Name|Role
            let parts = trimmed.components(separatedBy: "|")
            if parts.count >= 2 {
                let hex = parts[0].trimmingCharacters(in: .whitespaces)
                if hex.contains("#") {
                    colors.append(PaletteColor(
                        hex: hex, name: parts[1].trimmingCharacters(in: .whitespaces),
                        role: parts.count >= 3 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
                    ))
                    continue
                }
            }
            // Try dash format: #XXXXXX — Name — Role
            let dashParts = trimmed.components(separatedBy: " — ")
            if dashParts.count >= 2, dashParts[0].trimmingCharacters(in: .whitespaces).contains("#") {
                colors.append(PaletteColor(
                    hex: dashParts[0].trimmingCharacters(in: .whitespaces),
                    name: dashParts[1].trimmingCharacters(in: .whitespaces),
                    role: dashParts.count >= 3 ? dashParts[2].trimmingCharacters(in: .whitespaces) : ""
                ))
            }
        }
        return colors.isEmpty ? [PaletteColor(hex: fallbackHex, name: "Source", role: "Primary")] : colors
    }
}
