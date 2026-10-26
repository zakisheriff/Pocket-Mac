import SwiftUI
import Combine

struct MenuBarView: View {
    let frontmostApp: AppKind?
    var onAppleMenu: () -> Void = {}
    var onSpotlight: () -> Void = {}

    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 18) {
            Button(action: onAppleMenu) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            Text(frontmostApp?.displayName ?? "Finder")
                .font(.system(size: 13, weight: .bold))

            HStack(spacing: 14) {
                Text("File")
                Text("Edit")
                Text("View")
                Text("Window")
                Text("Help")
            }
            .font(.system(size: 13))
            .foregroundStyle(.primary.opacity(0.85))

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Button(action: onSpotlight) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                Text(timeString)
                    .monospacedDigit()
            }
            .font(.system(size: 13))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.001)) // keeps full-width hit testing without a hard edge
        .background(.ultraThinMaterial, in: Rectangle())
        .environment(\.colorScheme, .dark)
        .onReceive(clock) { now = $0 }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: now)
    }
}

#Preview {
    MenuBarView(frontmostApp: .safari)
        .background(Color.blue)
}
