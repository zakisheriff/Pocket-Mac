import SwiftUI

/// The physical "bottom half" deck used in Duo (folded laptop) mode:
/// keyboard up top, trackpad below — exactly where your thumbs land when
/// you hold the phone open like a tiny laptop.
struct TrackpadKeyboardView: View {
    @ObservedObject var cursor: CursorManager
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var keyboard: KeyboardInputManager

    var body: some View {
        VStack(spacing: 8) {
            KeyboardView(keyboard: keyboard)
            TrackpadView(cursor: cursor, windowManager: windowManager)
                .frame(maxHeight: .infinity)
        }
        .padding(10)
        .background(Color(white: 0.09))
    }
}
