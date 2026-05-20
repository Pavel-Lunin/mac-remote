# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# MacRemote — корневая память проекта

Управление MacBook с мобильного устройства по локальной сети.

## Monorepo-структура

Один git-репозиторий, две связанные кодовые базы и общая документация. Корневой `git` (см. `.git/` в корне) — единственный источник правды; внутри подпроектов своего git'а нет.

- [mac/](mac/) — Mac-приложение на SwiftUI (companion-сервер для приёма команд). **Пока пусто** — Swift-кода и Xcode-проекта ещё нет.
- [mobile/](mobile/) — мобильный клиент на Expo + TypeScript (iOS/Android). Полностью реализован; детали — в [mobile/CLAUDE.md](mobile/CLAUDE.md).
- [docs/protocol.md](docs/protocol.md) — единственный источник истины для протокола: транспорт, service discovery (Bonjour `_macremote._tcp.`), команды.

## Архитектурные принципы

- **Транспорт:** WebSocket в локальной Wi-Fi сети, REST как fallback.
- **Обнаружение:** Bonjour/mDNS, сервис `_macremote._tcp.`
- **Аутентификация:** Bearer-токен, выдаваемый Mac-приложением при первичном
  сопряжении (QR-код на экране Mac → сканирование с телефона).
- **Связь только локальная.** TLS не используется, cleartext HTTP/WS, потому
  что не выходим за пределы Wi-Fi. Не публиковать сервис в интернет.

## Контракт протокола

Полная спецификация — `docs/protocol.md`. При любом изменении протокола:

1. Сначала правится `docs/protocol.md`.
2. Затем синхронизируются обе стороны (`mac/` и `mobile/`).
3. Тип `CommandName` в `mobile/src/types/index.ts` должен совпадать
   с реестром команд в Swift-коде.

## Правила для агента

- При работе в `mobile/` дополнительно читай `mobile/CLAUDE.md`.
- При работе в `mac/` дополнительно читай `mac/CLAUDE.md`.
- Кросс-проектные изменения (новая команда, изменение протокола) делай
  единым коммитом, затрагивающим оба проекта.
- Не дублируй спецификацию протокола — ссылайся на `docs/protocol.md`.

## Команды

- Запустить мобильное приложение: `cd mobile && npx expo start`
- Открыть Mac-приложение: `open mac/MacRemote.xcodeproj` (далее в Xcode) — *появится после создания Xcode-проекта в `mac/`*
- Проверить типы мобильного: `cd mobile && npx tsc --noEmit`
- Линт мобильного: `cd mobile && npm run lint`

Дальнейшие команды для мобильного клиента (EAS-сборки, локальный native run, пр.) описаны в [mobile/CLAUDE.md](mobile/CLAUDE.md). Не дублировать их здесь.
