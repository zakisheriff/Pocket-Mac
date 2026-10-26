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

                Section("Trackpad") {
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

                Section("Gestures") {
                    GestureRow(symbol: "hand.point.up.left", title: "Move pointer", detail: "Slide one finger")
                    GestureRow(symbol: "hand.tap", title: "Click", detail: "Tap")
                    GestureRow(symbol: "hand.tap.fill", title: "Right-click", detail: "Tap with two fingers")
                    GestureRow(symbol: "arrow.up.and.down", title: "Scroll", detail: "Slide two fingers")
                    GestureRow(symbol: "hand.draw", title: "Drag or select", detail: "Press and hold, then slide")
                    GestureRow(symbol: "plus.magnifyingglass", title: "Zoom", detail: "Pinch (iPhone layout)")
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

private struct GestureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
