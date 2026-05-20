import { useRouter } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  RefreshControl,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  View,
} from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useThemeColor } from '@/hooks/use-theme-color';
import { Card } from '@/src/components/Card';
import { StatusDot } from '@/src/components/StatusDot';
import { VolumeSlider } from '@/src/components/VolumeSlider';
import { useRemoteClient } from '@/src/lib/RemoteClientContext';
import { clearSettings } from '@/src/lib/storage';
import type {
  SetVolumeArgs,
  OpenAppArgs,
  SystemInfo,
  VolumeResult,
} from '@/src/types';

const QUICK_APPS: { label: string; name: string }[] = [
  { label: 'Safari', name: 'Safari' },
  { label: 'Terminal', name: 'Terminal' },
  { label: 'VS Code', name: 'Visual Studio Code' },
  { label: 'Finder', name: 'Finder' },
  { label: 'Notes', name: 'Notes' },
];

const VOLUME_DEBOUNCE_MS = 120;

export default function ControlScreen() {
  const router = useRouter();
  const { client, status, settings, setActiveSettings } = useRemoteClient();

  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [volume, setVolume] = useState<number>(0);
  const [volumeKnown, setVolumeKnown] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [busyAction, setBusyAction] = useState<string | null>(null);

  const volumeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const tint = useThemeColor({}, 'tint');
  const iconColor = useThemeColor({}, 'icon');
  const dangerBg = '#F31260';

  const reportError = useCallback((label: string, err: unknown) => {
    const message = err instanceof Error ? err.message : String(err);
    Alert.alert(label, message);
  }, []);

  const refresh = useCallback(async () => {
    if (client === null) return;
    setRefreshing(true);
    try {
      const [info, vol] = await Promise.all([
        client.send<SystemInfo>('systemInfo'),
        client.send<VolumeResult>('getVolume'),
      ]);
      setSystemInfo(info);
      setVolume(vol.volume);
      setVolumeKnown(true);
    } catch (err) {
      reportError('Не удалось обновить данные', err);
    } finally {
      setRefreshing(false);
    }
  }, [client, reportError]);

  useEffect(() => {
    if (client !== null && status === 'connected') {
      void refresh();
    }
  }, [client, status, refresh]);

  useEffect(() => {
    return () => {
      if (volumeTimer.current !== null) {
        clearTimeout(volumeTimer.current);
      }
    };
  }, []);

  const scheduleVolumeSend = useCallback(
    (next: number) => {
      if (client === null) return;
      if (volumeTimer.current !== null) {
        clearTimeout(volumeTimer.current);
      }
      volumeTimer.current = setTimeout(() => {
        const args: SetVolumeArgs = { value: next };
        client.send<VolumeResult>('setVolume', args).catch((err: unknown) => {
          reportError('Не удалось задать громкость', err);
        });
      }, VOLUME_DEBOUNCE_MS);
    },
    [client, reportError],
  );

  const handleVolumeChange = useCallback((v: number) => {
    setVolume(v);
    setVolumeKnown(true);
  }, []);

  const handleVolumeCommit = useCallback(
    (v: number) => {
      scheduleVolumeSend(v);
    },
    [scheduleVolumeSend],
  );

  const adjustVolume = useCallback(
    (delta: number) => {
      const next = Math.max(0, Math.min(100, volume + delta));
      setVolume(next);
      setVolumeKnown(true);
      scheduleVolumeSend(next);
    },
    [volume, scheduleVolumeSend],
  );

  const runAction = useCallback(
    async (key: string, fn: () => Promise<void>) => {
      if (client === null) return;
      setBusyAction(key);
      try {
        await fn();
      } catch (err) {
        reportError('Ошибка', err);
      } finally {
        setBusyAction(null);
      }
    },
    [client, reportError],
  );

  const handleMuteToggle = () =>
    runAction('mute', async () => {
      if (client === null) return;
      const res = await client.send<VolumeResult>('muteToggle');
      setVolume(res.volume);
      setVolumeKnown(true);
    });

  const handleMedia = (cmd: 'mediaPlayPause' | 'mediaNext' | 'mediaPrev') =>
    runAction(cmd, async () => {
      if (client === null) return;
      await client.send<unknown>(cmd);
    });

  const handleOpenApp = (name: string) =>
    runAction(`open:${name}`, async () => {
      if (client === null) return;
      const args: OpenAppArgs = { name };
      await client.send<unknown>('openApp', args);
    });

  const handleLock = () =>
    runAction('lock', async () => {
      if (client === null) return;
      await client.send<unknown>('lockScreen');
    });

  const handleSleep = () => {
    Alert.alert('Sleep', 'Усыпить Mac?', [
      { text: 'Отмена', style: 'cancel' },
      {
        text: 'Усыпить',
        style: 'destructive',
        onPress: () =>
          runAction('sleep', async () => {
            if (client === null) return;
            await client.send<unknown>('sleep');
          }),
      },
    ]);
  };

  const handleDisconnect = () => {
    Alert.alert('Отключение', 'Удалить сохранённые настройки?', [
      { text: 'Отмена', style: 'cancel' },
      {
        text: 'Отключиться',
        style: 'destructive',
        onPress: async () => {
          await clearSettings();
          setActiveSettings(null);
          router.replace('/');
        },
      },
    ]);
  };

  const disabled = client === null || status !== 'connected';

  return (
    <ThemedView style={{ flex: 1 }}>
      <ScrollView
        contentContainerStyle={styles.scroll}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={refresh}
            tintColor={tint}
          />
        }
      >
        <Card>
          <View style={styles.statusRow}>
            <StatusDot status={status} />
            {busyAction !== null ? <ActivityIndicator color={tint} /> : null}
          </View>
          {settings !== null ? (
            <ThemedText style={{ color: iconColor }}>
              {settings.host}:{settings.port}
            </ThemedText>
          ) : null}
        </Card>

        <Card title="Система">
          {systemInfo === null ? (
            <ThemedText style={{ color: iconColor }}>—</ThemedText>
          ) : (
            <View style={styles.kvList}>
              <KV label="Hostname" value={systemInfo.hostname} />
              <KV label="Platform" value={systemInfo.platform} />
              <KV
                label="CPU"
                value={`${systemInfo.cpuModel} × ${systemInfo.cpuCount}`}
              />
              <KV
                label="Память"
                value={`${systemInfo.memFreeGB} / ${systemInfo.memTotalGB} GB`}
              />
              <KV label="Батарея" value={systemInfo.battery} />
              <KV label="Uptime" value={systemInfo.uptime} />
            </View>
          )}
        </Card>

        <Card title={`Громкость${volumeKnown ? `: ${volume}` : ''}`}>
          <VolumeSlider
            value={volume}
            onChange={handleVolumeChange}
            onCommit={handleVolumeCommit}
            disabled={disabled}
          />
          <View style={styles.row}>
            <ActionButton
              label="−10"
              onPress={() => adjustVolume(-10)}
              disabled={disabled}
            />
            <ActionButton
              label="Mute"
              onPress={handleMuteToggle}
              disabled={disabled}
            />
            <ActionButton
              label="+10"
              onPress={() => adjustVolume(10)}
              disabled={disabled}
            />
          </View>
        </Card>

        <Card title="Медиа">
          <View style={styles.row}>
            <ActionButton
              label="◀◀"
              onPress={() => handleMedia('mediaPrev')}
              disabled={disabled}
            />
            <ActionButton
              label="▶︎ / ❚❚"
              onPress={() => handleMedia('mediaPlayPause')}
              disabled={disabled}
            />
            <ActionButton
              label="▶▶"
              onPress={() => handleMedia('mediaNext')}
              disabled={disabled}
            />
          </View>
        </Card>

        <Card title="Быстрый запуск">
          <View style={styles.grid}>
            {QUICK_APPS.map((app) => (
              <ActionButton
                key={app.name}
                label={app.label}
                onPress={() => handleOpenApp(app.name)}
                disabled={disabled}
                style={styles.gridItem}
              />
            ))}
          </View>
        </Card>

        <Card title="Питание">
          <View style={styles.row}>
            <ActionButton
              label="Заблокировать"
              onPress={handleLock}
              disabled={disabled}
            />
            <ActionButton
              label="Усыпить"
              onPress={handleSleep}
              disabled={disabled}
              variant="danger"
            />
          </View>
        </Card>

        <TouchableOpacity
          onPress={handleDisconnect}
          style={[styles.disconnect, { backgroundColor: dangerBg }]}
        >
          <ThemedText
            type="defaultSemiBold"
            lightColor="#fff"
            darkColor="#fff"
          >
            Отключиться
          </ThemedText>
        </TouchableOpacity>
      </ScrollView>
    </ThemedView>
  );
}

type KVProps = { label: string; value: string };
function KV({ label, value }: KVProps) {
  const iconColor = useThemeColor({}, 'icon');
  return (
    <View style={styles.kvRow}>
      <ThemedText style={{ color: iconColor }}>{label}</ThemedText>
      <ThemedText style={styles.kvValue} numberOfLines={1}>
        {value}
      </ThemedText>
    </View>
  );
}

type ActionButtonProps = {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  variant?: 'default' | 'danger';
  style?: object;
};
function ActionButton({
  label,
  onPress,
  disabled,
  variant = 'default',
  style,
}: ActionButtonProps) {
  const tint = useThemeColor({}, 'tint');
  const surface = useThemeColor(
    { light: '#FFFFFF', dark: '#2A2D2F' },
    'background',
  );
  const border = useThemeColor({}, 'icon');
  const isDanger = variant === 'danger';
  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={disabled}
      style={[
        styles.actionBtn,
        {
          backgroundColor: isDanger ? '#F31260' : surface,
          borderColor: isDanger ? '#F31260' : border,
          opacity: disabled === true ? 0.45 : 1,
        },
        style,
      ]}
    >
      <ThemedText
        type="defaultSemiBold"
        lightColor={isDanger ? '#fff' : tint}
        darkColor={isDanger ? '#fff' : '#fff'}
      >
        {label}
      </ThemedText>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  scroll: {
    padding: 16,
    gap: 14,
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  kvList: {
    gap: 6,
  },
  kvRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 12,
  },
  kvValue: {
    flexShrink: 1,
    textAlign: 'right',
  },
  row: {
    flexDirection: 'row',
    gap: 10,
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  gridItem: {
    flexBasis: '30%',
    flexGrow: 1,
  },
  actionBtn: {
    flex: 1,
    paddingVertical: 12,
    paddingHorizontal: 10,
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  disconnect: {
    marginTop: 8,
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
  },
});
