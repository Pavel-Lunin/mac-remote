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
import { loadSettings, saveSettings } from '@/src/lib/storage';

const DEFAULT_PORT = 7777;

export default function ConnectScreen() {
  const router = useRouter();
  const { setActiveSettings } = useRemoteClient();

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
          <ThemedText style={{ color: iconColor }}>
            Введите адрес companion-сервера на вашем Mac.
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
    gap: 16,
  },
  centered: {
    justifyContent: 'center',
    alignItems: 'center',
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
