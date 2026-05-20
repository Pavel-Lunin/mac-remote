import { useCallback, useEffect, useRef, useState } from 'react';
import Zeroconf, { type ResolvedService } from 'react-native-zeroconf';

import type { DiscoveredService, DiscoveryStatus } from '@/src/types';

const SERVICE_TYPE = 'macremote';
const SERVICE_PROTOCOL = 'tcp';
const SERVICE_DOMAIN = 'local.';

function toDiscovered(service: ResolvedService): DiscoveredService {
  return {
    id: `${service.host}:${service.port}`,
    name: service.name,
    host: service.host,
    port: service.port,
    addresses: service.addresses,
  };
}

export type UseServiceDiscovery = {
  services: DiscoveredService[];
  status: DiscoveryStatus;
  error: string | null;
  start: () => void;
  stop: () => void;
};

export function useServiceDiscovery(): UseServiceDiscovery {
  const zeroconfRef = useRef<Zeroconf | null>(null);
  const [services, setServices] = useState<DiscoveredService[]>([]);
  const [status, setStatus] = useState<DiscoveryStatus>('idle');
  const [error, setError] = useState<string | null>(null);

  const getInstance = useCallback((): Zeroconf => {
    if (zeroconfRef.current === null) {
      zeroconfRef.current = new Zeroconf();
    }
    return zeroconfRef.current;
  }, []);

  const start = useCallback((): void => {
    const zc = getInstance();
    setError(null);
    setServices([]);
    setStatus('scanning');
    zc.scan(SERVICE_TYPE, SERVICE_PROTOCOL, SERVICE_DOMAIN);
  }, [getInstance]);

  const stop = useCallback((): void => {
    const zc = zeroconfRef.current;
    if (zc === null) return;
    zc.stop();
    setStatus('stopped');
  }, []);

  useEffect(() => {
    const zc = getInstance();

    const onResolved = (service: ResolvedService): void => {
      setServices((prev) => {
        const next = toDiscovered(service);
        const idx = prev.findIndex((s) => s.id === next.id);
        if (idx === -1) return [...prev, next];
        const copy = prev.slice();
        copy[idx] = next;
        return copy;
      });
    };

    const onRemove = (name: string): void => {
      setServices((prev) => prev.filter((s) => s.name !== name));
    };

    const onError = (err: Error): void => {
      setError(err.message);
      setStatus('error');
    };

    zc.on('resolved', onResolved);
    zc.on('remove', onRemove);
    zc.on('error', onError);

    return () => {
      zc.off('resolved', onResolved);
      zc.off('remove', onRemove);
      zc.off('error', onError);
      zc.stop();
      zc.removeDeviceListeners();
      zeroconfRef.current = null;
    };
  }, [getInstance]);

  return { services, status, error, start, stop };
}
