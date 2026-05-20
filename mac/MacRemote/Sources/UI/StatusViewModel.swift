import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI
import os

/// Состояние сервера для UI.
enum ServerStatus {
    case running(port: Int)
    case stopped
    case error(String)
}

/// ViewModel для menu-bar панели. Держит:
/// - актуальный токен и метод регенерации,
/// - статус сервера (для будущего рестарта в Этапе 10 — пока заглушка),
/// - флаг Accessibility-разрешения, опрашиваемый таймером раз в 2 сек.
@MainActor
final class StatusViewModel: ObservableObject {
    @Published private(set) var token: String
    @Published var status: ServerStatus = .stopped
    @Published private(set) var accessibilityGranted: Bool

    private let tokenStore: TokenStore
    private let log = Logger(subsystem: "com.macremote.app", category: "ui")
    private var permissionsTimer: Timer?

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        self.token = tokenStore.currentToken()
        self.accessibilityGranted = AXIsProcessTrusted()
        startPermissionsPolling()
    }

    deinit {
        // Timer.invalidate сам безопасен на любом потоке; @MainActor нужен только для
        // мутации Published, что в deinit уже неактуально.
        permissionsTimer?.invalidate()
    }

    // MARK: - Token

    func copyTokenToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(token, forType: .string)
        log.notice("token copied to pasteboard")
    }

    func regenerateToken() {
        token = tokenStore.regenerate()
        copyTokenToPasteboard()
    }

    // MARK: - Permissions polling

    private func startPermissionsPolling() {
        permissionsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = AXIsProcessTrusted()
                if granted != self.accessibilityGranted {
                    self.accessibilityGranted = granted
                    self.log.notice("Accessibility granted -> \(granted, privacy: .public)")
                }
            }
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Lifecycle

    func quit() {
        log.notice("Quit requested")
        NSApp.terminate(nil)
    }
}
