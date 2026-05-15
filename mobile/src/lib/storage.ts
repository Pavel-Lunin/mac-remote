import AsyncStorage from '@react-native-async-storage/async-storage';

import type { ConnectionSettings } from '@/src/types';

const STORAGE_KEY = '@macremote/settings';

function isConnectionSettings(value: unknown): value is ConnectionSettings {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.host === 'string' &&
    typeof v.port === 'number' &&
    typeof v.token === 'string'
  );
}

export async function loadSettings(): Promise<ConnectionSettings | null> {
  try {
    const raw = await AsyncStorage.getItem(STORAGE_KEY);
    if (raw === null) return null;
    const parsed: unknown = JSON.parse(raw);
    if (!isConnectionSettings(parsed)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export async function saveSettings(s: ConnectionSettings): Promise<void> {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(s));
}

export async function clearSettings(): Promise<void> {
  await AsyncStorage.removeItem(STORAGE_KEY);
}
