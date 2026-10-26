import SwiftUI

struct TrashAppView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Trash is Empty")
                .font(.system(size: 14, weight: .semibold))
            Text("Items moved to the Trash will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
