import { StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import type { ConnectionStatus } from '@/src/types';

const COLOR_BY_STATUS: Record<ConnectionStatus, string> = {
  idle: '#9BA1A6',
  connecting: '#F5A524',
  connected: '#17C964',
  disconnected: '#9BA1A6',
  error: '#F31260',
};

const LABEL_BY_STATUS: Record<ConnectionStatus, string> = {
  idle: 'не подключено',
  connecting: 'подключение…',
  connected: 'подключено',
  disconnected: 'отключено',
  error: 'ошибка',
};

type Props = {
  status: ConnectionStatus;
};

export function StatusDot({ status }: Props) {
  return (
    <View style={styles.row}>
      <View
        style={[styles.dot, { backgroundColor: COLOR_BY_STATUS[status] }]}
      />
      <ThemedText type="defaultSemiBold">{LABEL_BY_STATUS[status]}</ThemedText>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  dot: {
    width: 12,
    height: 12,
    borderRadius: 6,
  },
});
