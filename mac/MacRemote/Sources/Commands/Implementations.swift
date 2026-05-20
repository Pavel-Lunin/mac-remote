import AppKit
import CoreGraphics
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

/// Системные media-keys через CGEventPost. AppleScript-вариант `key code 16/17/18`
/// падает на локализованных macOS (русский парсер AppleScript ломается на
/// числовой константе после "key code"). CGEventPost — низкоуровневый и
/// независим от локали; требует Accessibility, как и AppleScript-варианты.
///
/// Коды берутся из <IOKit/hidsystem/ev_keymap.h>:
///   NX_KEYTYPE_PLAY = 16, NX_KEYTYPE_FAST = 17, NX_KEYTYPE_REWIND = 18.

private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_FAST: Int32 = 17
private let NX_KEYTYPE_REWIND: Int32 = 18

private func postMediaKey(_ keyCode: Int32) {
    func send(_ down: Bool) {
        let flags = NSEvent.ModifierFlags.init(rawValue: 0xa00)  // NX_SECONDARYFN+command-ish payload
        let data1 = Int((keyCode << 16) | ((down ? 0xa : 0xb) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,         // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
    send(true)
    send(false)
}

func cmdMediaPlayPause() async throws -> JSONValue {
    postMediaKey(NX_KEYTYPE_PLAY)
    return .null
}

func cmdMediaNext() async throws -> JSONValue {
    postMediaKey(NX_KEYTYPE_FAST)
    return .null
}

func cmdMediaPrev() async throws -> JSONValue {
    postMediaKey(NX_KEYTYPE_REWIND)
    return .null
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
