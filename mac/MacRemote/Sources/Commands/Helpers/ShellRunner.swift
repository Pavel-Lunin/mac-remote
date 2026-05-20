import Foundation
import os

enum ShellError: Error, CustomStringConvertible {
    case disallowedExecutable(String)

    var description: String {
        switch self {
        case .disallowedExecutable(let path):
            return "shell executable not in allowlist: \(path)"
        }
    }
}

/// Whitelist бинарей, которые серверу разрешено запускать. Никаких произвольных
/// команд — каждый абсолютный путь должен присутствовать в этом массиве.
private let allowedExecutables: Set<String> = [
    "/usr/bin/pmset",
    "/usr/bin/uptime",
    "/usr/sbin/sysctl",
    "/usr/bin/open",
]

private let shellLog = Logger(subsystem: "com.macremote.app", category: "commands")
private let shellTimeout: TimeInterval = 10

/// Запускает разрешённый шелл-бинарь с переданными аргументами. Возвращает stdout (trimmed).
/// Бросает `ShellError.disallowedExecutable`, если путь не из allowlist'а.
func runShell(executable: String, args: [String]) async throws -> String {
    guard allowedExecutables.contains(executable) else {
        shellLog.error("disallowed shell executable: \(executable, privacy: .public)")
        throw ShellError.disallowedExecutable(executable)
    }
    return try await runProcess(
        executable: executable,
        args: args,
        timeout: shellTimeout,
        logCategory: shellLog,
        logTag: "shell"
    )
}
