import Foundation
import os

/// Точка входа для исполнения команд протокола. Диспатчит `CommandName` на
/// конкретную реализацию в `Implementations.swift`.
final class CommandRunner {
    private let log = Logger(subsystem: "com.macremote.app", category: "commands")

    func run(cmd: CommandName, args: JSONValue?) async throws -> JSONValue {
        log.notice("→ \(cmd.rawValue, privacy: .public)")
        do {
            let result = try await dispatch(cmd: cmd, args: args)
            log.notice("✓ \(cmd.rawValue, privacy: .public)")
            return result
        } catch {
            log.error("✗ \(cmd.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func dispatch(cmd: CommandName, args: JSONValue?) async throws -> JSONValue {
        switch cmd {
        case .ping:           return cmdPing()
        case .systemInfo:     return try await cmdSystemInfo()
        case .getVolume:      return try await cmdGetVolume()
        case .setVolume:      return try await cmdSetVolume(args: args)
        case .muteToggle:     return try await cmdMuteToggle()
        case .mediaPlayPause: return try await cmdMediaPlayPause()
        case .mediaNext:      return try await cmdMediaNext()
        case .mediaPrev:      return try await cmdMediaPrev()
        case .openApp:        return try await cmdOpenApp(args: args)
        case .notify:         return try await cmdNotify(args: args)
        case .sleep:          return try await cmdSleep()
        case .lockScreen:     return try await cmdLockScreen()
        }
    }
}
