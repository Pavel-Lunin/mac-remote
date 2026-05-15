import { DarkTheme, DefaultTheme, ThemeProvider } from '@react-navigation/native';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import 'react-native-reanimated';

import { useColorScheme } from '@/hooks/use-color-scheme';
import { RemoteClientProvider } from '@/src/lib/RemoteClientContext';

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const theme = colorScheme === 'dark' ? DarkTheme : DefaultTheme;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <RemoteClientProvider>
        <ThemeProvider value={theme}>
          <Stack>
            <Stack.Screen
              name="index"
              options={{ title: 'Подключение' }}
            />
            <Stack.Screen
              name="control"
              options={{ title: 'MacRemote', headerBackVisible: false }}
            />
          </Stack>
          <StatusBar style="auto" />
        </ThemeProvider>
      </RemoteClientProvider>
    </GestureHandlerRootView>
  );
}
