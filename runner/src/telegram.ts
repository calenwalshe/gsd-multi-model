import { Bot, InlineKeyboard } from 'grammy';
import type { Notifier, TelegramConfig } from './types.js';

interface PendingGate {
  resolve: (approved: boolean) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout;
}

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

export class TelegramNotifier implements Notifier {
  private bot: Bot;
  private config: TelegramConfig;
  private log: Logger;
  private pendingGates = new Map<number, PendingGate>();
  private heartbeatInterval: NodeJS.Timeout | null = null;

  constructor(config: TelegramConfig, logger?: Logger) {
    this.config = config;
    this.log = logger ?? noopLogger;
    this.bot = new Bot(config.botToken);

    this.setupHandlers();
  }

  private setupHandlers(): void {
    // Gate approval/rejection handler
    this.bot.callbackQuery(/^gate:(approve|reject):(\d+)$/, async (ctx) => {
      const action = ctx.match![1];
      const gateId = parseInt(ctx.match![2]);
      const pending = this.pendingGates.get(gateId);

      if (!pending) {
        await ctx.answerCallbackQuery({ text: 'Gate expired or already handled' });
        return;
      }

      clearTimeout(pending.timer);
      this.pendingGates.delete(gateId);

      await ctx.answerCallbackQuery({
        text: action === 'approve' ? 'Approved' : 'Rejected',
      });
      await ctx.editMessageReplyMarkup();
      pending.resolve(action === 'approve');
    });

    // Catch-all for unmatched callback queries
    this.bot.on('callback_query:data', async (ctx) => {
      await ctx.answerCallbackQuery();
    });

    // Error handler
    this.bot.catch((err) => {
      this.log.error({ err: (err as { error?: unknown }).error ?? err }, 'grammY error');
    });
  }

  start(): void {
    this.bot.start({
      onStart: () => this.log.info('Telegram bot started polling'),
    });
  }

  async stop(): Promise<void> {
    this.stopHeartbeat();
    await this.bot.stop();
  }

  async requestGateApproval(message: string): Promise<boolean> {
    const gateId = Date.now();
    const keyboard = new InlineKeyboard()
      .text('Approve', `gate:approve:${gateId}`)
      .text('Reject', `gate:reject:${gateId}`);

    await this.bot.api.sendMessage(this.config.chatId, message, {
      reply_markup: keyboard,
      parse_mode: 'HTML',
    });

    return new Promise<boolean>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingGates.delete(gateId);
        reject(new Error(`Gate approval timed out after ${this.config.gateTimeoutMs}ms`));
      }, this.config.gateTimeoutMs);

      this.pendingGates.set(gateId, { resolve, reject, timer });
    });
  }

  async sendProgress(text: string): Promise<void> {
    await this.bot.api.sendMessage(this.config.chatId, text);
  }

  async sendAlert(text: string): Promise<void> {
    await this.bot.api.sendMessage(this.config.chatId, `\u26A0\uFE0F ${text}`);
  }

  startHeartbeat(): void {
    this.heartbeatInterval = setInterval(async () => {
      try {
        await this.bot.api.sendMessage(
          this.config.chatId,
          'GSD Runner heartbeat -- still running',
        );
      } catch (err) {
        this.log.warn({ err }, 'Heartbeat send failed');
      }
    }, this.config.heartbeatIntervalMs);
  }

  stopHeartbeat(): void {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }
}
