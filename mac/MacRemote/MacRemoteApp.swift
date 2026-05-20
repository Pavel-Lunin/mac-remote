import SwiftUI

@main
struct MacRemoteApp: App {
    var body: some Scene {
        MenuBarExtra("MacRemote", systemImage: "laptopcomputer") {
            StatusPanelView()
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}
