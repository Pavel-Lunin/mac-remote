import type {
  CommandName,
  ConnectionStatus,
  WireRequest,
  WireResponse,
} from '@/src/types';

const RECONNECT_DELAY_MS = 2000;
const REQUEST_TIMEOUT_MS = 8000;

export type RemoteClientOptions = {
  host: string;
  port: number;
  token: string;
  onStatus?: (s: ConnectionStatus) => void;
};

export type HealthResponse = {
  ok: boolean;
  name: string;
  version: number;
};

type PendingRequest = {
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
  timer: ReturnType<typeof setTimeout>;
};

function isWireResponse(value: unknown): value is WireResponse {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  if (typeof v.id !== 'string') return false;
  if (v.ok === true) return true;
  if (v.ok === false && typeof v.error === 'string') return true;
  return false;
}

function isHealthResponse(value: unknown): value is HealthResponse {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.ok === 'boolean' &&
    typeof v.name === 'string' &&
    typeof v.version === 'number'
  );
}

export class RemoteClient {
  private readonly host: string;
  private readonly port: number;
  private readonly token: string;
  private readonly onStatus?: (s: ConnectionStatus) => void;

  private ws: WebSocket | null = null;
  private shouldReconnect = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly pending = new Map<string, PendingRequest>();
  private requestCounter = 0;

  constructor(options: RemoteClientOptions) {
    this.host = options.host;
    this.port = options.port;
    this.token = options.token;
    this.onStatus = options.onStatus;
  }

  connect(): void {
    this.shouldReconnect = true;
    this.openSocket();
  }

  disconnect(): void {
    this.shouldReconnect = false;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws !== null) {
      try {
        this.ws.close();
      } catch {
        // ignore
      }
      this.ws = null;
    }
    this.rejectAllPending(new Error('disconnected'));
    this.emitStatus('disconnected');
  }

  async health(): Promise<HealthResponse> {
    const url = `http://${this.host}:${this.port}/health`;
    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`health http ${res.status}`);
    }
    const json: unknown = await res.json();
    if (!isHealthResponse(json)) {
      throw new Error('invalid health response');
    }
    return json;
  }

  async send<T>(cmd: CommandName, args?: unknown): Promise<T> {
    if (this.ws !== null && this.ws.readyState === 1) {
      return this.sendOverWs<T>(cmd, args);
    }
    return this.sendOverRest<T>(cmd, args);
  }

  private sendOverWs<T>(cmd: CommandName, args: unknown): Promise<T> {
    const ws = this.ws;
    if (ws === null) {
      return Promise.reject(new Error('ws not open'));
    }
    const id = this.nextId();
    const request: WireRequest = { id, cmd, args };
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`timeout: ${cmd}`));
      }, REQUEST_TIMEOUT_MS);
      this.pending.set(id, {
        resolve: (value: unknown) => resolve(value as T),
        reject,
        timer,
      });
      try {
        ws.send(JSON.stringify(request));
      } catch (err) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(err instanceof Error ? err : new Error(String(err)));
      }
    });
  }

  private async sendOverRest<T>(cmd: CommandName, args: unknown): Promise<T> {
    const url = `http://${this.host}:${this.port}/cmd`;
    const id = this.nextId();
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.token}`,
      },
      body: JSON.stringify({ id, cmd, args }),
    });
    if (!res.ok) {
      throw new Error(`rest http ${res.status}`);
    }
    const json: unknown = await res.json();
    if (typeof json !== 'object' || json === null) {
      throw new Error('invalid rest response');
    }
    const obj = json as Record<string, unknown>;
    if (obj.ok === false) {
      const message = typeof obj.error === 'string' ? obj.error : 'rest error';
      throw new Error(message);
    }
    if (obj.ok !== true) {
      throw new Error('invalid rest response');
    }
    return obj.result as T;
  }

  private openSocket(): void {
    this.emitStatus('connecting');
    const url = `ws://${this.host}:${this.port}/ws?token=${encodeURIComponent(this.token)}`;
    let ws: WebSocket;
    try {
      ws = new WebSocket(url);
    } catch {
      this.emitStatus('error');
      this.scheduleReconnect();
      return;
    }
    this.ws = ws;

    ws.onopen = () => {
      this.emitStatus('connected');
    };

    ws.onmessage = (event: WebSocketMessageEvent) => {
      this.handleMessage(event.data);
    };

    ws.onerror = () => {
      this.emitStatus('error');
    };

    ws.onclose = () => {
      this.ws = null;
      if (this.shouldReconnect) {
        this.emitStatus('disconnected');
        this.scheduleReconnect();
      }
    };
  }

  private handleMessage(data: unknown): void {
    if (typeof data !== 'string') return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(data);
    } catch {
      return;
    }
    if (!isWireResponse(parsed)) return;
    const pending = this.pending.get(parsed.id);
    if (pending === undefined) return;
    clearTimeout(pending.timer);
    this.pending.delete(parsed.id);
    if (parsed.ok) {
      pending.resolve(parsed.result);
    } else {
      pending.reject(new Error(parsed.error));
    }
  }

  private scheduleReconnect(): void {
    if (!this.shouldReconnect) return;
    if (this.reconnectTimer !== null) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (this.shouldReconnect) {
        this.openSocket();
      }
    }, RECONNECT_DELAY_MS);
  }

  private rejectAllPending(reason: Error): void {
    for (const [, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(reason);
    }
    this.pending.clear();
  }

  private emitStatus(s: ConnectionStatus): void {
    if (this.onStatus !== undefined) this.onStatus(s);
  }

  private nextId(): string {
    this.requestCounter += 1;
    return `${Date.now().toString(36)}-${this.requestCounter.toString(36)}`;
  }
}
