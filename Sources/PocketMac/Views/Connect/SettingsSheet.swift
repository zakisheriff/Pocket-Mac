import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Control", selection: Binding(
                        get: { settings.inputMode },
                        set: { settings.inputMode = $0 }
                    )) {
                        ForEach(InputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.inputModeRaw) { HapticsManager.selectionChanged() }
                } header: {
                    Text("Control")
                } footer: {
                    Text(settings.inputMode == .touch
                         ? "Touch: no pointer — tap an app or button to click it, swipe to scroll, hold and drag to move things. Like a touchscreen Mac."
                         : "Trackpad: slide to move the pointer and tap to click, just like a MacBook trackpad.")
                }

                Section {
                    Picker("Layout", selection: Binding(
                        get: { settings.layoutMode },
                        set: { settings.layoutMode = $0 }
                    )) {
                        ForEach(LayoutMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: settings.layoutModeRaw) { HapticsManager.selectionChanged() }
                } header: {
                    Text("Layout")
                } footer: {
                    Text("iPhone: the Mac fills the screen and the whole screen is your trackpad. iPhone Duo: hold the phone upright like an open laptop — the Mac on top, keyboard and trackpad below.")
                }

                if settings.inputMode == .trackpad {
                Section("Pointer") {
                    HStack(spacing: 10) {
                        ForEach(PointerStyle.allCases) { style in
                            PointerStyleOption(
                                style: style,
                                isSelected: settings.pointerStyle == style
                            ) {
                                HapticsManager.selectionChanged()
                                settings.pointerStyle = style
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pointer Size")
                        Slider(value: $settings.pointerSize, in: 14...56) {
                            Text("Pointer Size")
                        } minimumValueLabel: {
                            Image(systemName: "cursorarrow").font(.caption2)
                        } maximumValueLabel: {
                            Image(systemName: "cursorarrow").font(.title3)
                        } onEditingChanged: { _ in
                            HapticsManager.selectionChanged()
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Tracking Speed")
                        Slider(value: $settings.pointerSensitivity, in: 0.5...3.5) {
                            Text("Tracking Speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        } onEditingChanged: { _ in
                            HapticsManager.selectionChanged()
                        }
                    }
                }
                }

                Section("Scrolling") {
                    Toggle("Reverse Scrolling", isOn: $settings.reverseScrolling)
                        .onChange(of: settings.reverseScrolling) { HapticsManager.selectionChanged() }
                }

                Section("How to Use") {
                    if settings.inputMode == .touch {
                        GuideRow(symbol: "hand.tap", title: "Click", detail: "Tap right on it — tap twice to open")
                        GuideRow(symbol: "hand.tap.fill", title: "Right-click", detail: "Tap with two fingers")
                        GuideRow(symbol: "hand.draw", title: "Drag, move or select", detail: "Press and hold, then slide")
                        GuideRow(symbol: "arrow.up.and.down", title: "Scroll", detail: "Swipe with one finger")
                    } else {
                        GuideRow(symbol: "hand.point.up.left", title: "Move the pointer", detail: "Slide one finger anywhere")
                        GuideRow(symbol: "hand.tap", title: "Click", detail: "Tap once — tap twice to double-click")
                        GuideRow(symbol: "hand.tap.fill", title: "Right-click", detail: "Tap with two fingers")
                        GuideRow(symbol: "hand.draw", title: "Drag or select text", detail: "Press and hold, then slide")
                        GuideRow(symbol: "arrow.up.and.down", title: "Scroll", detail: "Slide two fingers")
                    }
                    GuideRow(symbol: "plus.magnifyingglass", title: "Zoom", detail: "Pinch with two fingers")
                    GuideRow(symbol: "arrow.up.and.down.and.arrow.left.and.right", title: "Move around when zoomed", detail: "Slide two fingers")
                    GuideRow(symbol: "command", title: "Shortcuts like ⌘C", detail: "Tap ⌘ then the key — double-tap a modifier to lock it")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticsManager.tap()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PointerStyleOption: View {
    let style: PointerStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(uiImage: PointerImages.image(for: style, pointerSize: 26))
                    .frame(width: 44, height: 44)
                    .background(Color(white: 0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                    )
                Text(style.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct GuideRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
