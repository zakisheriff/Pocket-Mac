import SwiftUI

struct FinderItem: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let tint: Color
    let kind: String
    let location: String
}

struct FinderAppView: View {
    @State private var selection: FinderItem.ID?
    @State private var activeLocation = "Recents"

    private let sidebar: [String] = ["Recents", "Desktop", "Documents", "Downloads", "Applications"]

    private let items: [FinderItem] = [
        FinderItem(name: "Applications", symbol: "square.grid.2x2.fill", tint: .blue, kind: "Folder", location: "Desktop"),
        FinderItem(name: "Desktop", symbol: "menubar.dock.rectangle", tint: .blue, kind: "Folder", location: "Desktop"),
        FinderItem(name: "Documents", symbol: "folder.fill", tint: .blue, kind: "Folder", location: "Documents"),
        FinderItem(name: "Downloads", symbol: "arrow.down.circle.fill", tint: .blue, kind: "Folder", location: "Downloads"),
        FinderItem(name: "Pocket Mac Notes.rtf", symbol: "doc.richtext.fill", tint: .gray, kind: "Document", location: "Documents"),
        FinderItem(name: "iPhone Duo Concept.psd", symbol: "photo.fill", tint: .indigo, kind: "Image", location: "Downloads"),
        FinderItem(name: "Build Log.txt", symbol: "doc.plaintext.fill", tint: .gray, kind: "Text", location: "Downloads"),
    ]

    private var visibleItems: [FinderItem] {
        activeLocation == "Recents" ? items : items.filter { $0.location == activeLocation }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(sidebar, id: \.self, selection: Binding(
                get: { activeLocation },
                set: { if let value = $0 { activeLocation = value; HapticsManager.selectionChanged() } }
            )) { entry in
                Label(entry, systemImage: icon(for: entry))
                    .font(.system(size: 12))
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 120)
            .environment(\.defaultMinListRowHeight, 22)

            Divider()

            ScrollView {
                if visibleItems.isEmpty {
                    Text("This folder is empty")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 14) {
                        ForEach(visibleItems) { item in
                            FinderIconCell(item: item, isSelected: selection == item.id) {
                                HapticsManager.selectionChanged()
                                selection = item.id
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Color.white)
    }

    fileprivate func icon(for entry: String) -> String {
        switch entry {
        case "Recents": return "clock.fill"
        case "Desktop": return "menubar.dock.rectangle"
        case "Documents": return "folder.fill"
        case "Downloads": return "arrow.down.circle.fill"
        default: return "cpu"
        }
    }
}

private struct FinderIconCell: View {
    let item: FinderItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: item.symbol)
                .font(.system(size: 26))
                .foregroundStyle(item.tint)
                .frame(width: 44, height: 36)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black.opacity(0.8))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
