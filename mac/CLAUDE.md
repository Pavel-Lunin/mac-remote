# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# mac/ — MacRemote companion server

Menu-bar приложение на SwiftUI + Vapor. Принимает команды от мобильного клиента ([../mobile/](../mobile/)) и выполняет их на macOS. Контракт протокола — в [../docs/protocol.md](../docs/protocol.md).

## Структура проекта

```
mac/
  MacRemote.xcodeproj/                — Xcode-проект (SPM-зависимость на Vapor)
  MacRemote/
    MacRemoteApp.swift                — @main, MenuBarExtra сцена, @StateObject AppCoordinator
    StatusPanelView.swift             — UI меню-бара
    Info.plist                        — LSUIElement=true, NSBonjourServices, NSLocalNetworkUsageDescription, NSAppleEventsUsageDescription
    MacRemote.entitlements            — sandbox OFF, network.server, network.client
    Assets.xcassets/
    Sources/
      Auth/TokenStore.swift           — Keychain под service "com.macremote.app", account "auth-token"
      Commands/
        Command.swift                 — CommandName enum, JSONValue, WireRequest/WireResponse Content
        CommandRunner.swift           — switch по CommandName, логирование вход/выход
        Implementations.swift         — все 13 команд
        Helpers/
          OsascriptRunner.swift       — Process + /usr/bin/osascript -e, 10s таймаут
          ShellRunner.swift           — allowlist /usr/bin/pmset, /usr/bin/uptime, /usr/sbin/sysctl, /usr/bin/open
      Discovery/BonjourPublisher.swift — NetService, _macremote._tcp.
      Server/VaporServer.swift        — Application.make + execute() в Task, /health /cmd /ws
      UI/AppCoordinator.swift         — @MainActor ObservableObject, владеет TokenStore/CommandRunner/VaporServer
```

Xcode использует **File System Synchronized Groups** (Xcode 16+) — новые файлы и подпапки в `MacRemote/` подцепляются автоматически. Не надо вручную добавлять файлы в `project.pbxproj`.

## Сборка и запуск

- CLI: `cd mac && xcodebuild -project MacRemote.xcodeproj -scheme MacRemote -configuration Debug -destination 'platform=macOS' build`. **`-destination 'platform=macOS'` обязательно** — без него xcodebuild подтягивает Mac Catalyst SDK, ловит конфликт с SwiftUICore и линковка падает.
- Через Xcode: открой `MacRemote.xcodeproj`, нажми Cmd+R.
- Первая сборка с Vapor долгая (~5-10 минут — компилируется весь NIO-стек). Последующие — секунды.

## Зависимости

**Vapor 4.x** через SwiftPM (File → Add Package Dependencies). К таргету привязан **только `Vapor`** — `VaporTesting` и `XCTVapor` нужно убрать вручную из Frameworks, иначе линковка падает (они требуют XCTest/Testing.framework, которые в app-таргете не работают).

Обновление: Xcode → File → Packages → Update to Latest Package Versions.

## Первый запуск — permissions

1. **Local Network** — система сама показывает prompt при первом `NetService.publish()`. Нажать Allow, иначе Bonjour не работает.
2. **Accessibility** — нужно для media-команд (`mediaPlayPause/Next/Prev` эмулируются через System Events). Выдать вручную в System Settings → Privacy & Security → Accessibility. В UI приложения есть кнопка «Open Settings», она открывает нужный раздел.
3. **Automation** — система запрашивает первый раз, когда osascript-команда дёргает System Events (например, mute). Просто нажать OK.

## Известные ограничения

- **Без App Sandbox.** Иначе ни `osascript` через `Process`, ни Bonjour на 0.0.0.0 не работают как нужно. Это компромисс local-only приложения.
- **Без login item.** Приложение не стартует автоматически при логине; запускать вручную из Applications или Xcode.
- **Без screenshot-команды.** Не запрашиваем Screen Recording permission. Удалено в v2 — см. [../docs/protocol.md](../docs/protocol.md).
- **Bundle ID** сейчас может быть `pavelunin-icloud.com.MacRemote` (Xcode подставил автоматически). Это нормально для local-only сборки. Subsystem для `os.Logger` (`com.macremote.app`) и Keychain service не зависят от Bundle ID.

## Pitfalls

- **CLI args для Vapor.** `Application.execute()` парсит `ProcessInfo.arguments` как Vapor-команды (`serve`, `routes`, …). Xcode в Debug передаёт свои флаги (`-NSDocumentRevisionsDebugMode`), и Vapor падает с `Unknown command`. Поэтому в `VaporServer.start()` мы создаём `Environment(arguments: ["MacRemote", "serve"])` явно. **Не убирать.**
- **`NetService` deprecated в macOS 14+** — но `NWListener.service` пришлось бы биндить на отдельный TCP-порт. Оставляем `NetService` пока он работает. Если когда-нибудь Apple реально удалит — переключимся на `NWListener` и поднимем порты в один.
- **`Info.plist` в Copy Bundle Resources.** При переключении проекта на физический Info.plist Xcode оставляет его и в Copy Bundle Resources, что вызывает warning. Убрать руками: target → Build Phases → Copy Bundle Resources → выделить Info.plist → `−`.
- **Логирование** — везде `Logger(subsystem: "com.macremote.app", category: ...)` с категориями `server`, `discovery`, `commands`, `auth`, `ui`. Просмотр: `/usr/bin/log show --predicate 'subsystem == "com.macremote.app"' --info --last 5m`.

## Логи в Vapor 4.121

Vapor свой Logger (`swift-log`) пишет в stderr. В Xcode они идут в Debug Console. Конфликт имён с `os.Logger` нужно явно разрешать через `os.Logger` в сигнатурах — `Vapor.Logger` (alias на `Logging.Logger`) и `os.Logger` одновременно в скоупе ловят compiler'у двусмысленность.
