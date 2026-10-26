import SwiftUI

/// Routes to the right bundled "app" view for a window's kind.
struct AppContentView: View {
    let kind: AppKind
    @ObservedObject var keyboard: KeyboardInputManager

    var body: some View {
        switch kind {
        case .finder:
            FinderAppView()
        case .notes:
            NotesAppView(keyboard: keyboard)
        case .safari:
            SafariAppView(keyboard: keyboard)
        case .calculator:
            CalculatorAppView()
        case .terminal:
            TerminalAppView(keyboard: keyboard)
        case .photos:
            PhotosAppView()
        case .settings:
            SettingsAppView()
        case .aboutThisMac:
            AboutThisMacView()
        case .trash:
            TrashAppView()
        }
    }
}
