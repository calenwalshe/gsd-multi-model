import type { GChatConfig, Notifier } from './types.js';

interface Logger {
  info: (msg: string | Record<string, unknown>, ...args: unknown[]) => void;
  warn: (msg: string | Record<string, unknown>, ...args: unknown[]) => void;
  error: (msg: string | Record<string, unknown>, ...args: unknown[]) => void;
}

const noopLogger: Logger = {
  info: () => {},
  warn: () => {},
  error: () => {},
};

interface GChatMessage {
  name: string;
  createTime: string;
  text: string;
}

/**
 * GChatNotifier — sends messages and polls for approvals via GChat REST API.
 *
 * Auth is a TODO stub: set GSD_GCHAT_AUTH_TOKEN or configure ADC/service account
 * before using this notifier in production. Without auth, postMessage will throw
 * with a clear error.
 */
export class GChatNotifier implements Notifier {
  private config: GChatConfig;
  private log: Logger;
  private heartbeatInterval: NodeJS.Timeout | null = null;
  private readonly baseUrl = 'https://chat.googleapis.com/v1';

  constructor(config: GChatConfig, logger?: Logger) {
    this.config = config;
    this.log = logger ?? noopLogger;
  }

  private getAuthHeader(): string {
    const token = process.env.GSD_GCHAT_AUTH_TOKEN;
    if (!token) {
      throw new Error(
        'GChat auth not configured. Set GSD_GCHAT_AUTH_TOKEN (bearer token) or ' +
        'implement ADC/service-account auth in runner/src/gchat.ts. ' +
        'See: https://developers.google.com/chat/api/guides/auth',
      );
    }
    return `Bearer ${token}`;
  }

  private async postMessage(text: string): Promise<GChatMessage> {
    const authHeader = this.getAuthHeader();
    const url = `${this.baseUrl}/${this.config.spaceId}/messages`;

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ text }),
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`GChat API error ${response.status}: ${body}`);
    }

    return response.json() as Promise<GChatMessage>;
  }

  private async listMessagesSince(since: string): Promise<GChatMessage[]> {
    const authHeader = this.getAuthHeader();
    const filter = encodeURIComponent(`createTime > "${since}"`);
    const url = `${this.baseUrl}/${this.config.spaceId}/messages?filter=${filter}&orderBy=createTime`;

    const response = await fetch(url, {
      headers: { 'Authorization': authHeader },
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`GChat API error ${response.status}: ${body}`);
    }

    const data = await response.json() as { messages?: GChatMessage[] };
    return data.messages ?? [];
  }

  private async pollForReply(
    since: string,
    timeoutMs: number,
  ): Promise<'approve' | 'reject' | 'timeout'> {
    const deadline = Date.now() + timeoutMs;

    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, this.config.pollIntervalMs));

      const messages = await this.listMessagesSince(since);
      for (const msg of messages) {
        const text = msg.text.toLowerCase().trim();
        if (text.includes('approve')) return 'approve';
        if (text.includes('reject')) return 'reject';
      }
    }

    return 'timeout';
  }

  async requestGateApproval(message: string): Promise<boolean> {
    const gateMessage = `${message}\n\nReply 'approve' to continue or 'reject' to halt.`;
    const sent = await this.postMessage(gateMessage);
    this.log.info({ createTime: sent.createTime }, 'GChat gate message sent');

    const result = await this.pollForReply(sent.createTime, this.config.gateTimeoutMs);

    if (result === 'timeout') {
      throw new Error(`Gate approval timed out after ${this.config.gateTimeoutMs}ms`);
    }

    this.log.info({ result }, 'GChat gate resolved');
    return result === 'approve';
  }

  async sendProgress(text: string): Promise<void> {
    await this.postMessage(text);
  }

  async sendAlert(text: string): Promise<void> {
    await this.postMessage(`⚠️ ${text}`);
  }

  startHeartbeat(): void {
    this.heartbeatInterval = setInterval(async () => {
      try {
        await this.postMessage('GSD Runner heartbeat -- still running');
      } catch (err) {
        this.log.warn({ err }, 'GChat heartbeat send failed');
      }
    }, this.config.heartbeatIntervalMs);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  async stop(): Promise<void> {
    this.stopHeartbeat();
  }
}
