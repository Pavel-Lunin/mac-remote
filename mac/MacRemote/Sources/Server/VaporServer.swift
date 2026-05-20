import Foundation
import Vapor
import NIOCore
import os

/// Vapor-сервер, обслуживающий `/health`, `/cmd` и WebSocket `/ws`.
///
/// Поведение:
/// - Health — без авторизации, отдаёт `{ ok, name, version }`.
/// - REST `/cmd` — проверяет `Authorization: Bearer <token>`, декодит `WireRequest`,
///   возвращает `WireResponse` (200 при успехе, 500 при ошибке команды, 401 при невалидном токене).
/// - WS `/ws?token=...` — проверяет токен в query на upgrade; если не совпал — `policyViolation` close.
///   На каждое текстовое сообщение декодит `WireRequest` и отвечает `WireResponse` JSON-строкой.
final class VaporServer {
    private let log = Logger(subsystem: "com.macremote.app", category: "server")
    private let port: Int
    private let commandRunner: CommandRunner
    private let tokenStore: TokenStore
    private let bonjour: BonjourPublisher
    private var app: Application?
    private var runTask: Task<Void, Error>?

    init(port: Int, commandRunner: CommandRunner, tokenStore: TokenStore) {
        self.port = port
        self.commandRunner = commandRunner
        self.tokenStore = tokenStore
        self.bonjour = BonjourPublisher()
    }

    /// Запускает сервер. Не блокирует — внутренний `Task` крутит цикл NIO.
    /// Throws, если порт занят (DI это ловит и пробует следующий — см. Этап 10).
    func start() async throws {
        // По умолчанию Vapor парсит ProcessInfo.processInfo.arguments как CLI-команды
        // (`serve`, `routes`, `migrate`, …). Xcode при Debug-запуске передаёт свои
        // флаги типа `-NSDocumentRevisionsDebugMode`, и Vapor падает с
        // "Unknown command". Передаём фиксированные args, чтобы он всегда запускал serve.
        let env = Environment(name: "development", arguments: ["MacRemote", "serve"])
        let app = try await Application.make(env)
        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = port

        // Декодинг JSON ContentType
        let decoder = JSONDecoder()
        ContentConfiguration.global.use(decoder: decoder, for: .json)

        registerRoutes(on: app)

        // Vapor: для запуска без блокировки main треда используем app.execute() в Task.
        // app.execute() сама bootstrap-ит сервер и крутит RunLoop NIO до shutdown.
        self.app = app
        self.runTask = Task { [log] in
            do {
                try await app.execute()
            } catch {
                log.error("Vapor execute() failed: \(String(describing: error), privacy: .public)")
                throw error
            }
        }
        log.notice("Vapor listening on port \(self.port, privacy: .public)")

        // Объявляем сервис в Bonjour: имя Mac + наш порт.
        let bonjourName = Host.current().localizedName ?? "MacBook"
        bonjour.publish(port: UInt16(port), name: bonjourName)
    }

    /// Корректная остановка: shutdown Vapor, отмена Task'а.
    func stop() async {
        log.notice("stopping Vapor")
        bonjour.unpublish()
        if let app {
            // shutdown — sync метод, после него execute() завершится.
            try? await app.asyncShutdown()
            self.app = nil
        }
        runTask?.cancel()
        runTask = nil
    }

    // MARK: - Routes

    private func registerRoutes(on app: Application) {
        let runner = commandRunner
        let tokens = tokenStore
        let log = self.log

        // GET /health — без авторизации
        app.get("health") { _ async throws -> HealthResponse in
            HealthResponse(
                ok: true,
                name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                version: 1
            )
        }

        // POST /cmd — Authorization: Bearer <token>
        app.post("cmd") { req async throws -> Response in
            guard let bearer = req.headers.bearerAuthorization, bearer.token == tokens.currentToken() else {
                log.notice("REST /cmd rejected: invalid token")
                throw Abort(.unauthorized, reason: "invalid token")
            }
            let wireRequest: WireRequest
            do {
                wireRequest = try req.content.decode(WireRequest.self)
            } catch {
                log.notice("REST /cmd rejected: bad request body")
                throw Abort(.badRequest, reason: "malformed WireRequest")
            }
            do {
                let result = try await runner.run(cmd: wireRequest.cmd, args: wireRequest.args)
                let payload = WireResponse.success(id: wireRequest.id, result: result)
                return try await payload.encodeResponse(status: .ok, for: req)
            } catch {
                let payload = WireResponse.failure(id: wireRequest.id, error: String(describing: error))
                return try await payload.encodeResponse(status: .internalServerError, for: req)
            }
        }

        // WS /ws?token=...
        app.webSocket(
            "ws",
            shouldUpgrade: { req async throws -> HTTPHeaders? in
                let token = (try? req.query.get(String.self, at: "token")) ?? ""
                if token == tokens.currentToken() {
                    return [:]
                }
                log.notice("WS upgrade rejected: invalid token")
                return nil
            },
            onUpgrade: { req, ws in
                log.notice("WS client connected")
                // Используем async-вариант onText: websocket-kit сам стартует Task,
                // привязанный к EventLoop сокета, и ws.send() из него безопасно.
                ws.onText { ws, text in
                    await VaporServer.handleWSText(text, ws: ws, runner: runner, log: log)
                }
                ws.onClose.whenComplete { _ in
                    log.notice("WS client disconnected")
                }
            }
        )
    }

    /// Обработать одно входящее WS-сообщение: декодит `WireRequest`, запускает команду,
    /// отправляет `WireResponse` обратно строкой.
    private static func handleWSText(_ text: String, ws: WebSocket, runner: CommandRunner, log: os.Logger) async {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        let wireRequest: WireRequest
        do {
            wireRequest = try decoder.decode(WireRequest.self, from: data)
        } catch {
            log.error("WS request decode failed: \(String(describing: error), privacy: .public)")
            // Без id ответить нечем — drop'аем по спеке.
            return
        }
        let response: WireResponse
        do {
            let result = try await runner.run(cmd: wireRequest.cmd, args: wireRequest.args)
            response = .success(id: wireRequest.id, result: result)
        } catch {
            response = .failure(id: wireRequest.id, error: String(describing: error))
        }
        do {
            let encoder = JSONEncoder()
            let bytes = try encoder.encode(response)
            guard let json = String(data: bytes, encoding: .utf8) else { return }
            try await ws.send(json)
        } catch {
            log.error("WS response send failed: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Auxiliary Content types

private struct HealthResponse: Content {
    let ok: Bool
    let name: String
    let version: Int
}
