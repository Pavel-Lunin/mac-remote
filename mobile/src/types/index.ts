export type ConnectionSettings = {
  host: string;
  port: number;
  token: string;
};

export type DiscoveredService = {
  id: string;
  name: string;
  host: string;
  port: number;
  addresses?: string[];
};

export type DiscoveryStatus = 'idle' | 'scanning' | 'stopped' | 'error';

export type ConnectionStatus =
  | 'idle'
  | 'connecting'
  | 'connected'
  | 'error'
  | 'disconnected';

export type CommandName =
  | 'ping'
  | 'systemInfo'
  | 'getVolume'
  | 'setVolume'
  | 'muteToggle'
  | 'mediaPlayPause'
  | 'mediaNext'
  | 'mediaPrev'
  | 'spotifyState'
  | 'openApp'
  | 'notify'
  | 'sleep'
  | 'lockScreen';

export type SystemInfo = {
  hostname: string;
  platform: string;
  cpuModel: string;
  cpuCount: number;
  memTotalGB: string;
  memFreeGB: string;
  battery: string;
  uptime: string;
};

export type VolumeResult = {
  volume: number;
};

export type SpotifyState = {
  running: boolean;
  state?: string;
  track?: string;
  artist?: string;
};

export type SetVolumeArgs = {
  value: number;
};

export type OpenAppArgs = {
  name: string;
};

export type NotifyArgs = {
  title?: string;
  message?: string;
};

export type WireRequest = {
  id: string;
  cmd: CommandName;
  args?: unknown;
};

export type WireResponse =
  | { id: string; ok: true; result: unknown }
  | { id: string; ok: false; error: string };
