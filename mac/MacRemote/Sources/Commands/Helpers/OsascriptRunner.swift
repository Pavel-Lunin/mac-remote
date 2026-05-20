import Foundation
import os

enum OsascriptError: Error, CustomStringConvertible {
    case nonZeroExit(code: Int32, stderr: String)
    case timeout
    case ioFailure(String)

    var description: String {
        switch self {
        case .nonZeroExit(let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "osascript exited with code \(code)"
                : "osascript exited with code \(code): \(trimmed)"
        case .timeout:
            return "osascript timed out"
        case .ioFailure(let message):
            return "osascript I/O failure: \(message)"
        }
    }
}

private let osascriptLog = Logger(subsystem: "com.macremote.app", category: "commands")
private let osascriptPath = "/usr/bin/osascript"
private let osascriptTimeout: TimeInterval = 10

/// Запускает AppleScript-строку через `/usr/bin/osascript -e <script>`.
/// Возвращает stdout (trimmed). Бросает `OsascriptError` при ненулевом exit,
/// таймауте или ошибке запуска процесса.
func runOsascript(_ script: String) async throws -> String {
    try await runProcess(
        executable: osascriptPath,
        args: ["-e", script],
        timeout: osascriptTimeout,
        logCategory: osascriptLog,
        logTag: "osascript"
    )
}

/// Общий хелпер для запуска внешнего процесса с таймаутом и захватом stdout/stderr.
/// Используется и osascript-раннером, и shell-раннером.
func runProcess(
    executable: String,
    args: [String],
    timeout: TimeInterval,
    logCategory: Logger,
    logTag: String
) async throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    return try await withCheckedThrowingContinuation { continuation in
        var didResume = false
        let resumeLock = NSLock()

        func resumeOnce(_ result: Result<String, Error>) {
            resumeLock.lock()
            defer { resumeLock.unlock() }
            if didResume { return }
            didResume = true
            continuation.resume(with: result)
        }

        process.terminationHandler = { proc in
            let stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stdoutString = String(data: stdout ?? Data(), encoding: .utf8) ?? ""
            let stderrString = String(data: stderr ?? Data(), encoding: .utf8) ?? ""
            if proc.terminationStatus == 0 {
                let trimmed = stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
                resumeOnce(.success(trimmed))
            } else {
                resumeOnce(.failure(OsascriptError.nonZeroExit(
                    code: proc.terminationStatus,
                    stderr: stderrString
                )))
            }
        }

        do {
            try process.run()
        } catch {
            logCategory.error("\(logTag, privacy: .public) failed to launch: \(error.localizedDescription, privacy: .public)")
            resumeOnce(.failure(OsascriptError.ioFailure(error.localizedDescription)))
            return
        }

        // Таймаут: убиваем процесс, если не успел.
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning {
                logCategory.error("\(logTag, privacy: .public) timeout after \(timeout, privacy: .public)s, terminating")
                process.terminate()
                resumeOnce(.failure(OsascriptError.timeout))
            }
        }
    }
}
