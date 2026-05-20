declare module 'react-native-zeroconf' {
  export type ResolvedService = {
    name: string;
    fullName?: string;
    host: string;
    port: number;
    addresses: string[];
    txt?: Record<string, string>;
  };

  export type ZeroconfEvent =
    | 'start'
    | 'stop'
    | 'error'
    | 'found'
    | 'remove'
    | 'resolved'
    | 'update';

  type Handler<E extends ZeroconfEvent> =
    E extends 'resolved' ? (service: ResolvedService) => void :
    E extends 'found' ? (name: string) => void :
    E extends 'remove' ? (name: string) => void :
    E extends 'error' ? (error: Error) => void :
    () => void;

  export default class Zeroconf {
    constructor();
    scan(type?: string, protocol?: string, domain?: string): void;
    stop(): void;
    getServices(): Record<string, ResolvedService>;
    removeDeviceListeners(): void;
    on<E extends ZeroconfEvent>(event: E, handler: Handler<E>): this;
    off<E extends ZeroconfEvent>(event: E, handler: Handler<E>): this;
    removeListener<E extends ZeroconfEvent>(event: E, handler: Handler<E>): this;
    removeAllListeners(event?: ZeroconfEvent): this;
  }
}
