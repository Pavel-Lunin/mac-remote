import SwiftUI

@main
struct MacRemoteApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("MacRemote", systemImage: "laptopcomputer") {
            StatusPanelView(coordinator: coordinator)
                .frame(width: 320)
                .task {
                    // Запускается один раз при первом появлении сцены.
                    await coordinator.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
