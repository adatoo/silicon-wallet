import SwiftUI

@main
struct SiliconWalletApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        #if os(macOS)
            .defaultSize(width: 1100, height: 700)
        #endif
        .commands {
            VaultCommands(model: model)
        }
    }
}
