import SwiftUI
import Combine

struct MenuBarView: View {
    let frontmostApp: AppKind?
    var onAppleMenu: () -> Void = {}
    var onSpotlight: () -> Void = {}

    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 460

            HStack(spacing: isCompact ? 10 : 18) {
                Button(action: onAppleMenu) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)

                Text(frontmostApp?.displayName ?? "Finder")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                if isCompact {
                    Text("⋯")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.85))
                } else {
                    HStack(spacing: 14) {
                        Text("File")
                        Text("Edit")
                        Text("View")
                        Text("Window")
                        Text("Help")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize()
                }

                Spacer(minLength: 8)

                HStack(spacing: isCompact ? 8 : 12) {
                    Image(systemName: "wifi")
                    if !isCompact {
                        Image(systemName: "battery.75")
                    }
                    Button(action: onSpotlight) {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    Text(timeString(compact: isCompact))
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .font(.system(size: 13))
            }
            .padding(.horizontal, 14)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(.white)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.001)) // keeps full-width hit testing without a hard edge
        .background(.ultraThinMaterial, in: Rectangle())
        .environment(\.colorScheme, .dark)
        .onReceive(clock) { now = $0 }
    }

    private func timeString(compact: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = compact ? "h:mm a" : "EEE h:mm a"
        return formatter.string(from: now)
    }
}

#Preview {
    MenuBarView(frontmostApp: .safari)
        .background(Color.blue)
}
