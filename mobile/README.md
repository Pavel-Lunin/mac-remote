# MacRemote

Mobile companion app for controlling a MacBook over the local network through a WebSocket/REST companion server (the server is maintained outside of this repo).

Built with Expo SDK 54, React Native 0.81, Expo Router, TypeScript and CNG (managed-config — no `ios/` / `android/` folders).

## Requirements

- Node.js + npm
- A development build of the app on a real iOS/Android device or a simulator/emulator.
  **Expo Go is not supported** — `app.json` includes native configuration (`NSAllowsLocalNetworking`, `usesCleartextTraffic`) that Expo Go cannot pick up.
- The phone/emulator and the Mac running the companion server must share the same Wi-Fi network.

## Run the dev server (Metro)

```bash
npm install
npx expo start
```

Then open the app from a development build on your device or simulator. From the Connect screen, enter the Mac's LAN IP, the companion server's port (default `7777`), and the token configured on the server.

## Build a development build

Pick whichever toolchain you already use:

- **EAS (cloud)** — recommended for shipping to a real device:
  ```bash
  npx eas build --profile development --platform ios
  npx eas build --profile development --platform android
  ```
- **Local native run** (requires Xcode / Android Studio toolchains):
  ```bash
  npx expo run:ios
  npx expo run:android
  ```

`npx expo run:*` will generate native `ios/` / `android/` folders on the fly via CNG — **don't commit them**. Native config stays in `app.json`.

## Project layout

- `app/` — Expo Router routes (Stack: `index` = Connect, `control` = main screen).
- `src/types/` — shared TypeScript types (`ConnectionSettings`, `CommandName`, command result types, wire envelopes).
- `src/lib/` — business logic: `RemoteClient` (WS + REST fallback), `storage` (typed AsyncStorage wrapper), `RemoteClientContext` (React provider).
- `src/components/` — `Card`, `StatusDot`, `VolumeSlider` (gesture-driven, no extra slider lib).
- `components/`, `hooks/`, `constants/` — the themed primitives and color/scheme helpers kept from the Expo template.

## Useful scripts

- `npm run lint` — ESLint via `expo lint`.
- `npx tsc --noEmit` — type-check the whole project.
- `npx expo export --platform ios|android` — sanity-check that the bundle builds.

## Notes

- Both `ws://` and `http://` to local hosts are explicitly enabled via `app.json` (iOS `NSAllowsLocalNetworking`, Android `usesCleartextTraffic`). This is scoped to local networking only.
- When testing against the Android emulator, the host machine is reachable as `10.0.2.2` (not `localhost`). On iOS Simulator, `localhost` works.
- Settings (host/port/token) are persisted in AsyncStorage under `@macremote/settings` — there is no `.env`.
