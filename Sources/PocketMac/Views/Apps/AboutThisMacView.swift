import SwiftUI
import UIKit

struct AboutThisMacView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "apple.logo")
                .font(.system(size: 52))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.top, 20)

            Text("Pocket Mac")
                .font(.system(size: 20, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                infoRow("Chip", "Pocket Silicon (on-device)")
                infoRow("Memory", memoryString)
                infoRow("Model Name", UIDevice.current.model)
                infoRow("System Version", "Pocket Mac 1.0, built on iOS \(UIDevice.current.systemVersion)")
                infoRow("Serial Number", serial)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()

            Text("© Pocket Mac — a simulated desktop for iPhone.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var memoryString: String {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb = Double(bytes) / 1_073_741_824
        return String(format: "%.0f GB", gb)
    }

    private var serial: String {
        String(UIDevice.current.identifierForVendor?.uuidString.prefix(12) ?? "POCKETMAC001")
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
    }
}
