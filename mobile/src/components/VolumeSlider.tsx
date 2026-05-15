import { useCallback, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  Gesture,
  GestureDetector,
  type PanGesture,
} from 'react-native-gesture-handler';

import { useThemeColor } from '@/hooks/use-theme-color';

type Props = {
  value: number;
  onChange: (v: number) => void;
  onCommit?: (v: number) => void;
  disabled?: boolean;
};

const TRACK_HEIGHT = 36;
const THUMB_SIZE = 28;

function clamp(value: number, min: number, max: number): number {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

export function VolumeSlider({ value, onChange, onCommit, disabled }: Props) {
  const [trackWidth, setTrackWidth] = useState(0);
  const [dragStartValue, setDragStartValue] = useState(0);

  const tint = useThemeColor({}, 'tint');
  const trackColor = useThemeColor(
    { light: '#E1E3E6', dark: '#2A2D2F' },
    'background',
  );

  const computeValue = useCallback(
    (translation: number, startValue: number): number => {
      if (trackWidth <= 0) return startValue;
      const delta = (translation / trackWidth) * 100;
      return clamp(Math.round(startValue + delta), 0, 100);
    },
    [trackWidth],
  );

  const gesture: PanGesture = Gesture.Pan()
    .enabled(disabled !== true)
    .onBegin(() => {
      setDragStartValue(value);
    })
    .onUpdate((e) => {
      const next = computeValue(e.translationX, dragStartValue);
      onChange(next);
    })
    .onEnd((e) => {
      const next = computeValue(e.translationX, dragStartValue);
      onChange(next);
      if (onCommit !== undefined) onCommit(next);
    })
    .runOnJS(true);

  const filledRatio = clamp(value, 0, 100) / 100;

  return (
    <GestureDetector gesture={gesture}>
      <View
        style={[styles.track, { backgroundColor: trackColor }]}
        onLayout={(e) => setTrackWidth(e.nativeEvent.layout.width)}
      >
        <View
          style={[
            styles.fill,
            { backgroundColor: tint, width: `${filledRatio * 100}%` },
          ]}
        />
        <View
          style={[
            styles.thumb,
            {
              backgroundColor: tint,
              left: Math.max(
                0,
                filledRatio * trackWidth - THUMB_SIZE / 2,
              ),
            },
          ]}
        />
      </View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  track: {
    height: TRACK_HEIGHT,
    borderRadius: TRACK_HEIGHT / 2,
    justifyContent: 'center',
    overflow: 'hidden',
  },
  fill: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    borderRadius: TRACK_HEIGHT / 2,
  },
  thumb: {
    position: 'absolute',
    width: THUMB_SIZE,
    height: THUMB_SIZE,
    borderRadius: THUMB_SIZE / 2,
    top: (TRACK_HEIGHT - THUMB_SIZE) / 2,
  },
});
