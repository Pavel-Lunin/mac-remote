import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useThemeColor } from '@/hooks/use-theme-color';
import { RemoteClient } from '@/src/lib/RemoteClient';
import { useRemoteClient } from '@/src/lib/RemoteClientContext';
import { useServiceDiscovery } from '@/src/lib/useServiceDiscovery';
import { loadSettings, saveSettings } from '@/src/lib/storage';
import type { DiscoveredService } from '@/src/types';

const DEFAULT_PORT = 7777;

export default function ConnectScreen() {
  const router = useRouter();
  const { setActiveSettings } = useRemoteClient();
  const discovery = useServiceDiscovery();

  const [host, setHost] = useState('');
  const [port, setPort] = useState(String(DEFAULT_PORT));
  const [token, setToken] = useState('');
  const [busy, setBusy] = useState(false);
  const [bootstrapping, setBootstrapping] = useState(true);

  const textColor = useThemeColor({}, 'text');
  const iconColor = useThemeColor({}, 'icon');
  const tint = useThemeColor({}, 'tint');
  const inputBg = useThemeColor(
    { light: '#F4F5F7', dark: '#1F2123' },
    'background',
  );
  const cardBg = useThemeColor(
    { light: '#FFFFFF', dark: '#1A1C1E' },
    'background',
  );
  const errorColor = useThemeColor(
    { light: '#C81E1E', dark: '#FF6B6B' },
    'text',
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const saved = await loadSettings();
      if (cancelled) return;
      if (saved !== null) {
        setActiveSettings(saved);
        router.replace('/control');
        return;
      }
      setBootstrapping(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [router, setActiveSettings]);

  if (bootstrapping) {
    return (
      <ThemedView style={[styles.container, styles.centered]}>
        <ActivityIndicator color={tint} />
      </ThemedView>
    );
  }

  const handlePickService = (svc: DiscoveredService): void => {
    setHost(svc.host);
    setPort(String(svc.port));
  };

  const toggleScan = (): void => {
    if (discovery.status === 'scanning') {
      discovery.stop();
    } else {
      discovery.start();
    }
  };

  const handleConnect = async () => {
    const trimmedHost = host.trim();
    const trimmedToken = token.trim();
    const portNum = Number.parseInt(port, 10);

    if (trimmedHost === '') {
      Alert.alert('Ошибка', 'Укажите host');
      return;
    }
    if (!Number.isFinite(portNum) || portNum <= 0 || portNum > 65535) {
      Alert.alert('Ошибка', 'Некорректный порт');
      return;
    }
    if (trimmedToken === '') {
      Alert.alert('Ошибка', 'Укажите token');
      return;
    }

    setBusy(true);
    const probe = new RemoteClient({
      host: trimmedHost,
      port: portNum,
      token: trimmedToken,
    });
    try {
      const health = await probe.health();
      if (!health.ok) {
        throw new Error(`сервер вернул ok=false (${health.name} v${health.version})`);
      }
      await probe.send<{ pong: true } | unknown>('ping');
      const settings = { host: trimmedHost, port: portNum, token: trimmedToken };
      await saveSettings(settings);
      setActiveSettings(settings);
      router.replace('/control');
    } catch (err) {
      const message = err instanceof Error ? err.message : 'неизвестная ошибка';
      Alert.alert('Не удалось подключиться', message);
    } finally {
      setBusy(false);
    }
  };

  const scanning = discovery.status === 'scanning';
  const hasServices = discovery.services.length > 0;

  return (
    <KeyboardAvoidingView
      style={{ flex: 1 }}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        contentContainerStyle={styles.scroll}
        keyboardShouldPersistTaps="handled"
      >
        <ThemedView style={styles.container}>
          <ThemedText type="title">MacRemote</ThemedText>

          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <ThemedText type="defaultSemiBold">Найденные устройства</ThemedText>
              <TouchableOpacity
                onPress={toggleScan}
                disabled={busy}
                style={[styles.scanButton, { borderColor: tint }]}
              >
                <ThemedText style={{ color: tint }}>
                  {scanning ? 'Остановить' : 'Искать'}
                </ThemedText>
              </TouchableOpacity>
            </View>

            {scanning && !hasServices ? (
              <View style={styles.scanInfo}>
                <ActivityIndicator color={tint} />
                <ThemedText style={{ color: iconColor }}>
                  Ищу MacBook в сети…
                </ThemedText>
              </View>
            ) : null}

            {discovery.status === 'error' && discovery.error !== null ? (
              <ThemedText style={{ color: errorColor }}>
                Ошибка поиска: {discovery.error}
              </ThemedText>
            ) : null}

            {!scanning && !hasServices && discovery.status !== 'error' ? (
              <ThemedText style={{ color: iconColor }}>
                Нажмите «Искать», чтобы найти Mac в локальной сети.
              </ThemedText>
            ) : null}

            {discovery.services.map((svc) => (
              <TouchableOpacity
                key={svc.id}
                onPress={() => handlePickService(svc)}
                disabled={busy}
                style={[styles.serviceCard, { backgroundColor: cardBg, borderColor: iconColor }]}
              >
                <ThemedText type="defaultSemiBold">{svc.name}</ThemedText>
                <ThemedText style={{ color: iconColor }}>
                  {svc.host}:{svc.port}
                </ThemedText>
              </TouchableOpacity>
            ))}
          </View>

          <View style={styles.section}>
            <ThemedText type="defaultSemiBold">Подключение</ThemedText>
            <ThemedText style={{ color: iconColor }}>
              Выберите устройство выше или введите адрес вручную.
            </ThemedText>

            <View style={styles.field}>
              <ThemedText type="defaultSemiBold">Host</ThemedText>
              <TextInput
                value={host}
                onChangeText={setHost}
                placeholder="192.168.1.10"
                placeholderTextColor={iconColor}
                autoCapitalize="none"
                autoCorrect={false}
                keyboardType="url"
                editable={!busy}
                style={[
                  styles.input,
                  { color: textColor, backgroundColor: inputBg, borderColor: iconColor },
                ]}
              />
            </View>

            <View style={styles.field}>
              <ThemedText type="defaultSemiBold">Port</ThemedText>
              <TextInput
                value={port}
                onChangeText={setPort}
                placeholder={String(DEFAULT_PORT)}
                placeholderTextColor={iconColor}
                keyboardType="number-pad"
                editable={!busy}
                style={[
                  styles.input,
                  { color: textColor, backgroundColor: inputBg, borderColor: iconColor },
                ]}
              />
            </View>

            <View style={styles.field}>
              <ThemedText type="defaultSemiBold">Token</ThemedText>
              <TextInput
                value={token}
                onChangeText={setToken}
                placeholder="секрет из конфига сервера"
                placeholderTextColor={iconColor}
                autoCapitalize="none"
                autoCorrect={false}
                secureTextEntry
                editable={!busy}
                style={[
                  styles.input,
                  { color: textColor, backgroundColor: inputBg, borderColor: iconColor },
                ]}
              />
            </View>

            <TouchableOpacity
              onPress={handleConnect}
              disabled={busy}
              style={[styles.button, { backgroundColor: tint, opacity: busy ? 0.6 : 1 }]}
            >
              {busy ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <ThemedText type="defaultSemiBold" lightColor="#fff" darkColor="#fff">
                  Подключиться
                </ThemedText>
              )}
            </TouchableOpacity>
          </View>
        </ThemedView>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flexGrow: 1,
  },
  container: {
    flex: 1,
    padding: 20,
    gap: 20,
  },
  centered: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  section: {
    gap: 12,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  scanButton: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
  },
  scanInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  serviceCard: {
    padding: 14,
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 4,
  },
  field: {
    gap: 6,
  },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 12,
    fontSize: 16,
  },
  button: {
    marginTop: 12,
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
  },
});
