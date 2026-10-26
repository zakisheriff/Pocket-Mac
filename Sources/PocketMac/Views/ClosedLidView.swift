import SwiftUI

/// Shown in Duo mode while the phone is held in portrait — the "lid closed"
/// state — prompting the user to rotate to open it like a laptop.
struct ClosedLidView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.75), Color(white: 0.5)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 46, weight: .thin))
                    .foregroundStyle(.white.opacity(0.9))

                VStack(spacing: 4) {
                    Text("Open the lid")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Rotate your iPhone sideways to unfold Pocket Mac")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)

                Image(systemName: "rotate.right")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.85))
                    .symbolEffect(.pulse)
            }
            .padding(32)
        }
    }
}

#Preview {
    ClosedLidView()
}
