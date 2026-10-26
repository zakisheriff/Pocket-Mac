import SwiftUI

struct SettingsAppView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Layout") {
                    VStack(spacing: 8) {
                        ForEach(LayoutMode.allCases) { mode in
                            modeRow(mode)
                        }
                    }
                    Text("iPhone Duo mode splits the screen into a desktop and a physical keyboard deck, like folding a laptop shut. Regular iPhones use direct touch with an optional floating trackpad.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                section("Desktop Picture") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 10) {
                        ForEach(WallpaperOption.allCases) { option in
                            wallpaperSwatch(option)
                        }
                    }
                }

                section("Trackpad") {
                    Toggle("Show floating trackpad", isOn: $settings.trackpadOverlayEnabled)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tracking speed")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.pointerSensitivity, in: 0.6...3.0)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.white)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func modeRow(_ mode: LayoutMode) -> some View {
        let isSelected = settings.layoutMode == mode
        return HStack {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(mode.displayName)
                .font(.system(size: 13))
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticsManager.selectionChanged()
            settings.layoutMode = mode
        }
    }

    private func wallpaperSwatch(_ option: WallpaperOption) -> some View {
        let isSelected = settings.wallpaper == option
        return VStack(spacing: 4) {
            option.gradient
                .aspectRatio(16.0 / 10.0, contentMode: .fill)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
            Text(option.displayName)
                .font(.system(size: 10))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticsManager.selectionChanged()
            settings.wallpaper = option
        }
    }
}
