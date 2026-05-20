import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI
import os

enum ServerStatus: Equatable {
    case starting
    case running(port: Int)
    case stopped
    case error(String)
}

/// Главный координатор приложения. Один инстанс на сессию: создаётся в `MacRemoteApp`
/// как `@StateObject`. Владеет `TokenStore`, `CommandRunner`, текущим `VaporServer`,
/// и предоставляет состояние/действия для `StatusPanelView`.
@MainActor
final class AppCoordinator: ObservableObject {
    /// Список портов для попытки старта: 7777, 7778, …, 7781 (5 попыток).
    private static let portCandidates: [Int] = Array(7777...7781)

    @Published private(set) var token: String
    @Published private(set) var status: ServerStatus = .stopped
    @Published private(set) var accessibilityGranted: Bool

    private let tokenStore: TokenStore
    private let commandRunner: CommandRunner
    private var server: VaporServer?
    private var permissionsTimer: Timer?
    private let log = Logger(subsystem: "com.macremote.app", category: "ui")

    init() {
        let tokenStore = TokenStore()
        self.tokenStore = tokenStore
        self.commandRunner = CommandRunner()
        self.token = tokenStore.currentToken()
        self.accessibilityGranted = AXIsProcessTrusted()
        startPermissionsPolling()
    }

    deinit {
        permissionsTimer?.invalidate()
    }

    // MARK: - Server lifecycle

    /// Стартует сервер, перебирая порты-кандидаты при `bind failed`.
    /// Безопасно вызывать повторно — сначала остановит предыдущий.
    func start() async {
        await stop()
        status = .starting
        for port in Self.portCandidates {
            let candidate = VaporServer(
                port: port,
                commandRunner: commandRunner,
                tokenStore: tokenStore
            )
            do {
                try await candidate.start()
                self.server = candidate
                self.status = .running(port: port)
                log.notice("server started on port \(port, privacy: .public)")
                return
            } catch {
                log.error("failed to start on port \(port, privacy: .public): \(String(describing: error), privacy: .public)")
                // Если start() частично поднял Vapor (а потом упал) — корректно гасим.
                await candidate.stop()
            }
        }
        self.status = .error("Не удалось занять ни один из портов \(Self.portCandidates.first!)…\(Self.portCandidates.last!)")
        log.error("all port candidates exhausted")
    }

    /// Останавливает текущий сервер (если есть).
    func stop() async {
        if let server {
            await server.stop()
            self.server = nil
        }
        if status != .stopped {
            status = .stopped
        }
    }

    /// Удобный рестарт.
    func restart() async {
        await start()
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

    // MARK: - Permissions

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

    // MARK: - Quit

    func quit() async {
        log.notice("Quit requested — shutting down server")
        await stop()
        NSApp.terminate(nil)
    }
}
