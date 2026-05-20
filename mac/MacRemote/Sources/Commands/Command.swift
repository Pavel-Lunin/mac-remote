import Foundation
import Vapor

// MARK: - CommandName

/// Регистр команд протокола. `screenshot` удалён в v2 (Swift implementation).
enum CommandName: String, Codable, CaseIterable, Sendable {
    case ping
    case systemInfo
    case getVolume
    case setVolume
    case muteToggle
    case mediaPlayPause
    case mediaNext
    case mediaPrev
    case spotifyState
    case openApp
    case notify
    case sleep
    case lockScreen
}

// MARK: - JSONValue

/// Произвольное JSON-значение для `args` и `result`. Поддерживает все типы JSON:
/// null, bool, number (через Double), string, array, object.
///
/// `Int` распознаётся при декодировании отдельно, чтобы не терять точность для разумных
/// целых; при кодировании всё число всё равно становится одним литералом JSON-number.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
            return
        }
        if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }

    // Удобные аксессоры

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.rounded() == d && d >= Double(Int.min) && d <= Double(Int.max):
            return Int(d)
        default: return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

// MARK: - Wire envelopes

/// Запрос от клиента: WS или REST `/cmd`.
struct WireRequest: Content {
    let id: String
    let cmd: CommandName
    let args: JSONValue?
}

/// Ответ серверу клиенту. Сериализуется как один из двух вариантов:
/// `{ id, ok: true, result }` или `{ id, ok: false, error }`.
struct WireResponse: Content {
    let id: String
    let ok: Bool
    let result: JSONValue?
    let error: String?

    static func success(id: String, result: JSONValue) -> WireResponse {
        WireResponse(id: id, ok: true, result: result, error: nil)
    }

    static func failure(id: String, error: String) -> WireResponse {
        WireResponse(id: id, ok: false, result: nil, error: error)
    }

    enum CodingKeys: String, CodingKey {
        case id, ok, result, error
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ok, forKey: .ok)
        if ok, let result {
            try c.encode(result, forKey: .result)
        }
        if !ok, let error {
            try c.encode(error, forKey: .error)
        }
    }
}
