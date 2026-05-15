import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';

import { RemoteClient } from '@/src/lib/RemoteClient';
import type { ConnectionSettings, ConnectionStatus } from '@/src/types';

export type RemoteClientContextValue = {
  client: RemoteClient | null;
  status: ConnectionStatus;
  settings: ConnectionSettings | null;
  setActiveSettings: (s: ConnectionSettings | null) => void;
};

const RemoteClientContext = createContext<RemoteClientContextValue | null>(null);

type Props = {
  children: ReactNode;
};

export function RemoteClientProvider({ children }: Props) {
  const [settings, setSettings] = useState<ConnectionSettings | null>(null);
  const [status, setStatus] = useState<ConnectionStatus>('idle');
  const [client, setClient] = useState<RemoteClient | null>(null);

  useEffect(() => {
    if (settings === null) {
      setClient(null);
      setStatus('idle');
      return;
    }

    const instance = new RemoteClient({
      host: settings.host,
      port: settings.port,
      token: settings.token,
      onStatus: (s) => setStatus(s),
    });
    setClient(instance);
    instance.connect();

    return () => {
      instance.disconnect();
    };
  }, [settings]);

  const setActiveSettings = useCallback((s: ConnectionSettings | null) => {
    setSettings(s);
  }, []);

  const value = useMemo<RemoteClientContextValue>(
    () => ({ client, status, settings, setActiveSettings }),
    [client, status, settings, setActiveSettings],
  );

  return (
    <RemoteClientContext.Provider value={value}>
      {children}
    </RemoteClientContext.Provider>
  );
}

export function useRemoteClient(): RemoteClientContextValue {
  const ctx = useContext(RemoteClientContext);
  if (ctx === null) {
    throw new Error('useRemoteClient must be used inside RemoteClientProvider');
  }
  return ctx;
}
