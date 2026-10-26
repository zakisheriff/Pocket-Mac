import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Pointer") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Pointer Size")
                            Spacer()
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5)
                                .frame(width: settings.pointerSize, height: settings.pointerSize)
                                .frame(width: 60, height: 60)
                        }
                        Slider(value: $settings.pointerSize, in: 14...56) {
                            Text("Pointer Size")
                        } minimumValueLabel: {
                            Image(systemName: "circle").font(.caption2)
                        } maximumValueLabel: {
                            Image(systemName: "circle").font(.title3)
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
                    Toggle("Reverse Scrolling", isOn: $settings.reverseScrolling)
                        .onChange(of: settings.reverseScrolling) { HapticsManager.selectionChanged() }
                }

                Section("How to Use") {
                    GuideRow(symbol: "hand.point.up.left", title: "Move the pointer", detail: "Slide one finger anywhere")
                    GuideRow(symbol: "hand.tap", title: "Click", detail: "Tap once — tap twice to double-click")
                    GuideRow(symbol: "hand.tap.fill", title: "Right-click", detail: "Tap with two fingers")
                    GuideRow(symbol: "hand.draw", title: "Drag or select text", detail: "Press and hold, then slide")
                    GuideRow(symbol: "arrow.up.and.down", title: "Scroll", detail: "Slide two fingers")
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
