# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

Managed Expo app (CNG — no `ios/` / `android/` folders, all native config in `app.json`). MacRemote is a mobile client for a Mac companion server on the local network: WebSocket-first transport with REST fallback, persistent connection settings, and a single Control screen that exposes system info, volume, media, app launching, power and screenshots.

Two routes exist in `app/`: `index` (Connect) and `control` (main screen). Business logic lives in `src/`. Boot logic is in `app/index.tsx` — on launch it reads `loadSettings()` and `router.replace('/control')` if the user has connected before.

## Commands

- `npm start` / `npx expo start` — Metro dev server (works with a development build of MacRemote — **not Expo Go**, see below).
- `npm run ios` / `npm run android` / `npm run web` — Metro targeting a specific platform.
- `npx expo run:ios` / `npx expo run:android` — generate native projects on the fly (via CNG) and build locally. Don't commit the generated `ios/` / `android/` folders.
- `npx eas build --profile development --platform ios|android` — cloud development build for a real device.
- `npm run lint` — ESLint via `expo lint`.
- `npx tsc --noEmit` — strict type-check across the project.
- `npx expo export --platform ios|android` — sanity-check that the bundle builds end-to-end.
- `npm run reset-project` — template helper from `create-expo-app`. Don't run it now: we already removed the template screens and moved business logic into `src/`. Kept around in case it's needed; consider deleting `scripts/reset-project.js` later.

No test setup yet.

## Architecture

- **Routing**: `expo-router` with file-based routing. `app/_layout.tsx` is the root `Stack` wrapped in `GestureHandlerRootView` and `RemoteClientProvider`. Routes:
  - `app/index.tsx` — Connect screen (host/port/token form, calls `client.health()` + `ping` and persists on success).
  - `app/control.tsx` — main control screen.
  - Typed routes (`typedRoutes` experiment) are on, so route strings are checked.
- **Path alias**: `@/*` maps to the repo root (`tsconfig.json`). Import as `@/components/...`, `@/src/lib/...`, `@/src/types`, etc.
- **Theming**: `constants/theme.ts` holds `Colors` (light/dark). `useColorScheme` (`hooks/use-color-scheme.ts` + `.web.ts` variant) picks the scheme; `useThemeColor` resolves a color for the current scheme. `ThemedText` / `ThemedView` are the primitives — prefer them over raw `Text` / `View`.
- **Platform-specific files**: `.ios.tsx` / `.web.ts` suffix convention (e.g. `components/ui/icon-symbol.ios.tsx`, `hooks/use-color-scheme.web.ts`). Metro resolves per platform.
- **New Architecture** (`newArchEnabled`) and **React Compiler** (`reactCompiler` experiment) are on — avoid manual memoization patterns the compiler handles.
- **Business logic in `src/`**, separate from the route tree:
  - `src/types/index.ts` — shared types: `ConnectionSettings`, `ConnectionStatus`, `CommandName` (union of every server command), per-command arg/result types (`SystemInfo`, `VolumeResult`, `SpotifyState`, `ScreenshotResult`, `SetVolumeArgs`, `OpenAppArgs`, `NotifyArgs`), and wire envelopes `WireRequest` / `WireResponse`.
  - `src/lib/storage.ts` — typed AsyncStorage wrapper for `ConnectionSettings` under key `@macremote/settings` (`loadSettings`/`saveSettings`/`clearSettings`); `loadSettings` swallows parse errors and validates shape before returning.
  - `src/lib/RemoteClient.ts` — `RemoteClient` class: WebSocket to `ws://{host}:{port}/ws?token=...` with ~2s reconnect backoff, in-flight request map with ~8s timeouts, REST fallback via `POST /cmd` (`Authorization: Bearer {token}`) when the socket isn't open, and `health()` against `GET /health`. Status changes are reported through the optional `onStatus` callback. No `any` — incoming WS payloads are validated as `WireResponse` before dispatch.
  - `src/lib/RemoteClientContext.tsx` — React provider (`RemoteClientProvider`) holding the active `RemoteClient` and current `ConnectionStatus`, plus `useRemoteClient()` hook. The provider owns the client lifecycle: changing `settings` tears down the previous client and connects a new one; `setActiveSettings(null)` disconnects.
  - `src/lib/useServiceDiscovery.ts` — React-хук поверх `react-native-zeroconf`. Сканирует `_macremote._tcp.` в домене `local.`, возвращает `{ services, status, error, start, stop }`. Один инстанс `Zeroconf` хранится в `useRef`, при размонтировании компонент снимает слушатели, вызывает `zc.stop()` и `removeDeviceListeners()`. Скан не запускается автоматически — `start()` вызывается явно из UI. Payload события `remove` библиотеки — **строка `name`** (а не объект), удаляем сервис по совпадению `service.name === name`. ID для UI формируется как `host:port`, чтобы тот же сервер не задвоился при повторном `resolved`.
  - `src/components/Card.tsx`, `StatusDot.tsx`, `VolumeSlider.tsx` — UI primitives. `VolumeSlider` is a gesture-driven slider built on `react-native-gesture-handler`'s `Gesture.Pan()` — **do not** add a separate slider library.

## Server command contract

The companion server speaks these commands (consumed via `client.send<T>(cmd, args)`):

| Command          | Args                       | Result type        |
|------------------|----------------------------|--------------------|
| `ping`           | —                          | `unknown` (truthy) |
| `systemInfo`     | —                          | `SystemInfo`       |
| `getVolume`      | —                          | `VolumeResult`     |
| `setVolume`      | `SetVolumeArgs {value}`    | `VolumeResult`     |
| `muteToggle`     | —                          | `VolumeResult`     |
| `mediaPlayPause` | —                          | `unknown`          |
| `mediaNext`      | —                          | `unknown`          |
| `mediaPrev`      | —                          | `unknown`          |
| `spotifyState`   | —                          | `SpotifyState`     |
| `openApp`        | `OpenAppArgs {name}`       | `unknown`          |
| `notify`         | `NotifyArgs {title?,message?}` | `unknown`      |
| `sleep`          | —                          | `unknown`          |
| `lockScreen`     | —                          | `unknown`          |
| `screenshot`     | —                          | `ScreenshotResult` |

Wire envelope is `WireRequest` → `WireResponse` over WS; REST uses the same `{cmd, args}` body with `Authorization: Bearer {token}` and returns the same envelope.

## Config

- App metadata, plugins and platform settings: `app.json`.
- `strict: true` in `tsconfig.json` — keep it that way; no `any`.
- Local cleartext networking is explicitly allowed:
  - iOS: `infoPlist.NSAppTransportSecurity.NSAllowsLocalNetworking = true` + `NSLocalNetworkUsageDescription`.
  - Android: `usesCleartextTraffic = true`.
  These are scoped to local networking — don't widen them to global cleartext.
- Service discovery (Bonjour/mDNS):
  - iOS: `infoPlist.NSBonjourServices = ["_macremote._tcp"]`. Without this entry, iOS silently refuses to resolve our service type. The service-type list is closed at build time — adding a new service later requires a rebuild.
  - Android: `permissions` includes `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `INTERNET`. Without `CHANGE_WIFI_MULTICAST_STATE` NSD won't see anything on real devices.

## Pitfalls

- **Don't use Expo Go**. `app.json` carries native config (`NSAllowsLocalNetworking`, `usesCleartextTraffic`, `NSLocalNetworkUsageDescription`) that Expo Go doesn't pick up. Always use a development build.
- **Android emulator hostname**: from the AVD, the host Mac is `10.0.2.2`, not `localhost`. iOS Simulator can use `localhost`.
- **Don't edit `ios/` / `android/` by hand** — they shouldn't exist in this repo. Native config goes through `app.json` (CNG). If `expo run:*` creates them locally, treat them as ephemeral build output.
- **Don't bump package versions manually**. Install with `npx expo install <pkg>` so SDK 54-compatible versions are picked.
- **`react-native-zeroconf` requires a fresh native build**. It's a native module, so any new install or change to `NSBonjourServices` / Android `permissions` in `app.json` means the previous dev build is stale. Re-run `npx expo run:ios|android` or `npx eas build --profile development` and reinstall on the device. Expo Go doesn't ship this module — service discovery silently does nothing there.
- **Gesture handler root**: `GestureHandlerRootView` wraps the whole app in `app/_layout.tsx`. Adding gesture-based components elsewhere requires no extra setup, but removing that wrapper will silently break `VolumeSlider`.
