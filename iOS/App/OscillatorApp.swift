import OscillatorUI
import SwiftUI

/// The iOS app: a thin shell around the screens shared with the macOS app (OscillatorUI).
@main
struct OscillatorApp: App {
    @State private var model = OscillatorModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
