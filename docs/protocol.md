# MacRemote Protocol

Спецификация протокола между Mac-приложением (companion-сервер) и мобильным клиентом. Этот документ — единственный источник истины. При любом изменении протокола сначала правится он, затем синхронизируются `mac/` и `mobile/`.

## Transport

- WebSocket: `ws://{host}:{port}/ws?token={token}` — основной канал.
- REST fallback: `POST http://{host}:{port}/cmd` c `Authorization: Bearer {token}`, тело `{ cmd, args }`.
- Health: `GET http://{host}:{port}/health` — без авторизации, для probe из Connect-экрана.

Связь только локальная (Wi-Fi LAN), cleartext HTTP/WS, без TLS.

## Service Discovery (Bonjour / mDNS)

Mac-приложение **обязано** объявлять сервис при запуске, чтобы мобильный клиент мог найти его без ручного ввода адреса.

- **Тип сервиса:** `_macremote._tcp.`
- **Домен:** `local.`
- **Порт:** тот же, что у HTTP/WS-сервера (по умолчанию `7777`).
- **Имя инстанса:** имя Mac (например, `Pavel’s MacBook`). Должно быть человекочитаемым — оно покажется в списке найденных устройств.

### TXT-записи (опционально, зарезервировано)

Ключи, которые мобильный клиент будет читать в будущем. Сейчас не обязательны, но при добавлении нужно следовать этому реестру:

| Ключ      | Тип     | Описание                                 |
|-----------|---------|------------------------------------------|
| `version` | string  | Версия протокола, например `"1"`.        |
| `name`    | string  | Дублирует имя Mac, если bonjour-имя инстанса искажено системой (длина / кодировка). |

Новые TXT-ключи добавлять только через этот документ.

### Поведение клиента

- Сканирование запускается явно (по нажатию «Искать»), не автоматически.
- Найденный сервис заполняет поля `host` и `port` в форме подключения. Токен по-прежнему вводится вручную (до реализации QR-pairing).

## Authentication

Bearer-токен, выдаваемый Mac-приложением при первичном сопряжении (планируется QR-код на экране Mac → сканирование с телефона).

## Commands

Регистр команд (`CommandName` в `mobile/src/types/index.ts` должен совпадать с реестром в Swift-коде):

| Command          | Args                            | Result                                                       |
|------------------|---------------------------------|--------------------------------------------------------------|
| `ping`           | —                               | `{ ok: true, hostname: string, platform: "macOS" }`          |
| `systemInfo`     | —                               | `SystemInfo`                                                 |
| `getVolume`      | —                               | `VolumeResult`                                               |
| `setVolume`      | `{ value: number }` (0..100)    | `VolumeResult`                                               |
| `muteToggle`     | —                               | `VolumeResult`                                               |
| `mediaPlayPause` | —                               | `null`                                                       |
| `mediaNext`      | —                               | `null`                                                       |
| `mediaPrev`      | —                               | `null`                                                       |
| `spotifyState`   | —                               | `SpotifyState`                                               |
| `openApp`        | `{ name: string }`              | `null`                                                       |
| `notify`         | `{ title?: string, message?: string }` | `null`                                                |
| `sleep`          | —                               | `null`                                                       |
| `lockScreen`     | —                               | `null`                                                       |
| ~~`screenshot`~~ | ~~—~~                           | **removed in v2 (Swift implementation)**                     |

### Result types

- `SystemInfo`: `{ hostname, platform, cpuModel, cpuCount, memTotalGB, memFreeGB, battery, uptime }` — все поля строкового или числового скаляра, формат человекочитаемый.
- `VolumeResult`: `{ volume: number }` — 0..100, целое. Mute эмулируется отдельным полем или `volume === 0`; см. реализацию.
- `SpotifyState`: `{ running: boolean, state?: "playing" | "paused" | "stopped", track?: string, artist?: string }`. Если Spotify не запущен — `{ running: false }`, остальные поля отсутствуют.

### Wire envelopes

Тот же формат для WS и REST. Сообщение — JSON-объект.

**Request:**
```json
{ "id": "<string>", "cmd": "<CommandName>", "args": <JSON value or null> }
```

**Response (success):**
```json
{ "id": "<string>", "ok": true, "result": <JSON value> }
```

**Response (error):**
```json
{ "id": "<string>", "ok": false, "error": "<human-readable string>" }
```

`id` клиент придумывает сам (UUID или счётчик), сервер возвращает его как есть для сопоставления.

## Implementation notes

- **Mac-сервер**: SwiftUI menu-bar app + Vapor (Swift) поверх SwiftNIO. WebSocket — `app.webSocket("ws") { req, ws in … }`; REST — `app.post("cmd") { req in … }`; health — `app.get("health") { … }`.
- **Команды macOS** реализованы через `osascript` (`Process` + `/usr/bin/osascript -e`) и небольшой allowlist shell-утилит (`pmset`, `uptime`, `sysctl`, `open`). Никаких произвольных команд серверу извне выполнить нельзя.
- **Permissions** на стороне macOS: Accessibility (для media-keys через System Events) — пользователь даёт вручную; Automation (Spotify, System Events) — система запрашивает при первой команде. Без этих разрешений соответствующие команды вернут ошибку с понятным текстом, остальные продолжат работать.
- **Формат ошибок (бизнес-логика)**: при любой ошибке выполнения (osascript non-zero exit, нет разрешения, неизвестная команда, невалидные args) сервер отвечает `{ id, ok: false, error }` с HTTP 500 (REST) или таким же JSON через WS.
- **Формат ошибок (транспортные)**: ошибки до запуска команды отдаются стандартным Vapor-форматом `{ "error": true, "reason": "<message>" }` с HTTP-кодом — `401` для невалидного/отсутствующего Bearer-токена, `400` для невалидного JSON в теле. У них нет `id`, потому что мы не успели распарсить запрос. Клиент должен различать форматы по HTTP-коду: 200/500 → парсить как `WireResponse`, 401/400 → парсить как `{error,reason}`.
- WS-ошибки авторизации отдаются на этапе HTTP upgrade (403 от Vapor, до открытия WebSocket); после успешного upgrade всё уходит в тело `WireResponse`.
