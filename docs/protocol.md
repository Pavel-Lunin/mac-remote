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

| Command          | Args                            | Result type        |
|------------------|---------------------------------|--------------------|
| `ping`           | —                               | `unknown` (truthy) |
| `systemInfo`     | —                               | `SystemInfo`       |
| `getVolume`      | —                               | `VolumeResult`     |
| `setVolume`      | `{ value: number }`             | `VolumeResult`     |
| `muteToggle`     | —                               | `VolumeResult`     |
| `mediaPlayPause` | —                               | `unknown`          |
| `mediaNext`      | —                               | `unknown`          |
| `mediaPrev`      | —                               | `unknown`          |
| `spotifyState`   | —                               | `SpotifyState`     |
| `openApp`        | `{ name: string }`              | `unknown`          |
| `notify`         | `{ title?, message? }`          | `unknown`          |
| `sleep`          | —                               | `unknown`          |
| `lockScreen`     | —                               | `unknown`          |
| `screenshot`     | —                               | `ScreenshotResult` |

Wire-конверт WS — `WireRequest` → `WireResponse`. REST использует то же тело `{cmd, args}` и тот же ответ.
