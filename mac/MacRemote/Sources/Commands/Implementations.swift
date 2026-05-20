import Foundation
import os

enum CommandError: Error, CustomStringConvertible {
    case invalidArgs(String)
    case execution(String)

    var description: String {
        switch self {
        case .invalidArgs(let msg): return "invalid args: \(msg)"
        case .execution(let msg): return msg
        }
    }
}

private let log = Logger(subsystem: "com.macremote.app", category: "commands")

// MARK: - Ping

func cmdPing() -> JSONValue {
    let hostname = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    return .object([
        "ok": .bool(true),
        "hostname": .string(hostname),
        "platform": .string("macOS"),
    ])
}

// MARK: - System info

func cmdSystemInfo() async throws -> JSONValue {
    async let battery = (try? await runShell(executable: "/usr/bin/pmset", args: ["-g", "batt"])) ?? "n/a"
    async let uptime = (try? await runShell(executable: "/usr/bin/uptime", args: [])) ?? "n/a"
    async let cpuModel = (try? await runShell(executable: "/usr/sbin/sysctl", args: ["-n", "machdep.cpu.brand_string"])) ?? "n/a"
    async let cpuCountStr = (try? await runShell(executable: "/usr/sbin/sysctl", args: ["-n", "hw.ncpu"])) ?? "0"
    async let memTotalStr = (try? await runShell(executable: "/usr/sbin/sysctl", args: ["-n", "hw.memsize"])) ?? "0"

    let host = Host.current()
    let hostname = host.localizedName ?? ProcessInfo.processInfo.hostName
    let platform = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"

    let cpuCount = Int(await cpuCountStr) ?? 0
    let memTotalBytes = UInt64(await memTotalStr) ?? 0
    let memTotalGB = String(format: "%.1f", Double(memTotalBytes) / 1024 / 1024 / 1024)

    // memFree: vm_stat — но его нет в allowlist; берём через хост-статистики Mach.
    let memFreeGB = String(format: "%.1f", machFreeMemoryGB())

    return .object([
        "hostname": .string(hostname),
        "platform": .string(platform),
        "cpuModel": .string(await cpuModel),
        "cpuCount": .int(cpuCount),
        "memTotalGB": .string(memTotalGB),
        "memFreeGB": .string(memFreeGB),
        "battery": .string(await battery),
        "uptime": .string(await uptime),
    ])
}

private func machFreeMemoryGB() -> Double {
    var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    var stats = vm_statistics64_data_t()
    let host = mach_host_self()
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            host_statistics64(host, HOST_VM_INFO64, $0, &size)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    let pageSize = UInt64(vm_kernel_page_size)
    let freeBytes = UInt64(stats.free_count) * pageSize
    return Double(freeBytes) / 1024 / 1024 / 1024
}

// MARK: - Volume

func cmdGetVolume() async throws -> JSONValue {
    let raw = try await runOsascript("output volume of (get volume settings)")
    let value = Int(raw) ?? 0
    return .object(["volume": .int(value)])
}

func cmdSetVolume(args: JSONValue?) async throws -> JSONValue {
    guard let v = args?.objectValue?["value"]?.intValue else {
        throw CommandError.invalidArgs("setVolume requires { value: number }")
    }
    let clamped = max(0, min(100, v))
    _ = try await runOsascript("set volume output volume \(clamped)")
    return .object(["volume": .int(clamped)])
}

func cmdMuteToggle() async throws -> JSONValue {
    let mutedRaw = try await runOsascript("output muted of (get volume settings)")
    let currentlyMuted = mutedRaw.lowercased() == "true"
    let next = !currentlyMuted
    _ = try await runOsascript("set volume \(next ? "with" : "without") output muted")
    let volRaw = try await runOsascript("output volume of (get volume settings)")
    let vol = Int(volRaw) ?? 0
    return .object([
        "volume": .int(vol),
        "muted": .bool(next),
    ])
}

// MARK: - Media

func cmdMediaPlayPause() async throws -> JSONValue {
    _ = try await runOsascript("tell application \"System Events\" to key code 16 using {function down}")
    return .null
}

func cmdMediaNext() async throws -> JSONValue {
    _ = try await runOsascript("tell application \"System Events\" to key code 17 using {function down}")
    return .null
}

func cmdMediaPrev() async throws -> JSONValue {
    _ = try await runOsascript("tell application \"System Events\" to key code 18 using {function down}")
    return .null
}

// MARK: - Spotify

func cmdSpotifyState() async throws -> JSONValue {
    let runningRaw = try await runOsascript("tell application \"System Events\" to (name of processes) contains \"Spotify\"")
    let isRunning = runningRaw.lowercased() == "true"
    if !isRunning {
        return .object(["running": .bool(false)])
    }
    let state = (try? await runOsascript("tell application \"Spotify\" to player state as string")) ?? ""
    let track = (try? await runOsascript("tell application \"Spotify\" to name of current track as string")) ?? ""
    let artist = (try? await runOsascript("tell application \"Spotify\" to artist of current track as string")) ?? ""
    var obj: [String: JSONValue] = ["running": .bool(true)]
    if !state.isEmpty { obj["state"] = .string(state) }
    if !track.isEmpty { obj["track"] = .string(track) }
    if !artist.isEmpty { obj["artist"] = .string(artist) }
    return .object(obj)
}

// MARK: - Open app

private let appNameAllowedCharset: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: " .-")
    return set
}()

func cmdOpenApp(args: JSONValue?) async throws -> JSONValue {
    guard let name = args?.objectValue?["name"]?.stringValue, !name.isEmpty else {
        throw CommandError.invalidArgs("openApp requires { name: string }")
    }
    if name.rangeOfCharacter(from: appNameAllowedCharset.inverted) != nil {
        throw CommandError.invalidArgs("openApp name contains disallowed characters")
    }
    _ = try await runShell(executable: "/usr/bin/open", args: ["-a", name])
    return .null
}

// MARK: - Notify

func cmdNotify(args: JSONValue?) async throws -> JSONValue {
    let title = args?.objectValue?["title"]?.stringValue ?? "MacRemote"
    let message = args?.objectValue?["message"]?.stringValue ?? ""
    let safeTitle = escapeAppleScriptString(title)
    let safeMessage = escapeAppleScriptString(message)
    _ = try await runOsascript("display notification \"\(safeMessage)\" with title \"\(safeTitle)\"")
    return .null
}

private func escapeAppleScriptString(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - Sleep / lock

func cmdSleep() async throws -> JSONValue {
    _ = try await runShell(executable: "/usr/bin/pmset", args: ["sleepnow"])
    return .null
}

func cmdLockScreen() async throws -> JSONValue {
    _ = try await runShell(executable: "/usr/bin/pmset", args: ["displaysleepnow"])
    return .null
}
