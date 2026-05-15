import { StyleSheet, View, type ViewProps } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { useThemeColor } from '@/hooks/use-theme-color';

type Props = ViewProps & {
  title?: string;
};

export function Card({ title, children, style, ...rest }: Props) {
  const background = useThemeColor(
    { light: '#F4F5F7', dark: '#1F2123' },
    'background',
  );
  const border = useThemeColor(
    { light: '#E1E3E6', dark: '#2A2D2F' },
    'icon',
  );

  return (
    <View
      style={[
        styles.card,
        { backgroundColor: background, borderColor: border },
        style,
      ]}
      {...rest}
    >
      {title !== undefined ? (
        <ThemedText type="subtitle" style={styles.title}>
          {title}
        </ThemedText>
      ) : null}
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 14,
    padding: 16,
    gap: 10,
  },
  title: {
    marginBottom: 4,
  },
});
