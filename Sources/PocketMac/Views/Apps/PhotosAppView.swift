import SwiftUI

struct PhotosAppView: View {
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 4)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<24, id: \.self) { index in
                    WallpaperOption.allCases[index % WallpaperOption.allCases.count].gradient
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(6)
        }
        .background(Color.white)
    }
}
