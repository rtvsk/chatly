import {
  Injectable,
  Logger,
  OnApplicationBootstrap,
  OnApplicationShutdown,
} from '@nestjs/common';
import { and, eq, sql } from 'drizzle-orm';
import { isMailSendEvent, MAIL_SEND_PATTERN } from '@app/contracts';

import { DatabaseService } from '../database/database.service';
import { outboxEvents } from '../database/schema';
import { MailPublisher } from './mail.publisher';

const POLL_INTERVAL_MS = 1_000;
const BATCH_SIZE = 50;
const CONCURRENCY = 5;
const LEASE_MS = 60_000;
const BACKOFF_MS = [1_000, 5_000, 30_000, 120_000, 300_000] as const;

interface ClaimedEvent {
  id: string;
  topic: string;
  payload: unknown;
  attempts: number;
  expiresAt: Date;
}

export const outboxBackoffMs = (
  attempt: number,
  random: () => number = Math.random,
): number => {
  const base =
    BACKOFF_MS[Math.min(Math.max(attempt - 1, 0), BACKOFF_MS.length - 1)];
  const jitter = 0.8 + random() * 0.4;
  return Math.round(base * jitter);
};

@Injectable()
export class OutboxDispatcherService
  implements OnApplicationBootstrap, OnApplicationShutdown
{
  private readonly logger = new Logger(OutboxDispatcherService.name);
  private readonly inFlight = new Set<Promise<unknown>>();
  private timer?: ReturnType<typeof setInterval>;
  private activePoll?: Promise<void>;
  private polling = false;
  private stopping = false;

  constructor(
    private readonly database: DatabaseService,
    private readonly mailPublisher: MailPublisher,
  ) {}

  onApplicationBootstrap(): void {
    this.timer = setInterval(() => this.startPoll(), POLL_INTERVAL_MS);
    this.startPoll();
  }

  async onApplicationShutdown(): Promise<void> {
    this.stopping = true;
    if (this.timer) {
      clearInterval(this.timer);
    }
    await this.activePoll;
    await Promise.allSettled([...this.inFlight]);
  }

  async dispatchNow(eventId: string): Promise<boolean> {
    if (this.stopping) {
      return false;
    }

    return this.track(this.dispatchOne(eventId));
  }

  private async dispatchOne(eventId: string): Promise<boolean> {
    await this.expireEvents(eventId);
    const [event] = await this.claimEvents(1, eventId);
    if (!event) {
      return false;
    }

    return this.dispatch(event);
  }

  private startPoll(): void {
    if (this.polling || this.stopping) {
      return;
    }

    this.polling = true;
    const poll = this.runPoll();
    this.activePoll = poll;
    void poll.then(
      () => {
        this.polling = false;
        this.activePoll = undefined;
      },
      () => {
        this.polling = false;
        this.activePoll = undefined;
      },
    );
  }

  private async runPoll(): Promise<void> {
    try {
      await this.expireEvents();
      const events = await this.claimEvents(BATCH_SIZE);

      for (let offset = 0; offset < events.length; offset += CONCURRENCY) {
        const batch = events.slice(offset, offset + CONCURRENCY);
        await Promise.all(
          batch.map((event) => this.track(this.dispatch(event))),
        );
      }
    } catch (error) {
      this.logger.error(`Outbox polling failed: ${this.describeError(error)}`);
    }
  }

  private async claimEvents(
    limit: number,
    eventId?: string,
  ): Promise<ClaimedEvent[]> {
    const idFilter = eventId ? sql`AND "id" = ${eventId}` : sql``;
    const result = await this.database.db.execute(sql`
      WITH candidates AS (
        SELECT "id"
        FROM "outbox_events"
        WHERE (
          ("status" = 'pending' AND "availableAt" <= now())
          OR ("status" = 'processing' AND "lockedUntil" <= now())
        )
        AND "expiresAt" > now()
        ${idFilter}
        ORDER BY "createdAt"
        FOR UPDATE SKIP LOCKED
        LIMIT ${limit}
      )
      UPDATE "outbox_events" AS event
      SET
        "status" = 'processing',
        "lockedUntil" = now() + ${LEASE_MS} * interval '1 millisecond',
        "updatedAt" = now()
      FROM candidates
      WHERE event."id" = candidates."id"
      RETURNING
        event."id",
        event."topic",
        event."payload",
        event."attempts",
        event."expiresAt"
    `);

    return result.rows as unknown as ClaimedEvent[];
  }

  private async dispatch(event: ClaimedEvent): Promise<boolean> {
    if (event.topic !== MAIL_SEND_PATTERN || !isMailSendEvent(event.payload)) {
      await this.markDead(event.id, 'Invalid outbox event');
      return false;
    }

    if (
      event.payload.template === 'email-verification' &&
      Date.parse(event.payload.expiresAt) <= Date.now()
    ) {
      await this.markDead(event.id, 'Verification event expired');
      return false;
    }

    try {
      await this.mailPublisher.publish(event.payload);
      const now = new Date();
      await this.database.db
        .update(outboxEvents)
        .set({
          status: 'published',
          payload: null,
          lockedUntil: null,
          publishedAt: now,
          lastError: null,
          updatedAt: now,
        })
        .where(
          and(
            eq(outboxEvents.id, event.id),
            eq(outboxEvents.status, 'processing'),
          ),
        );
      return true;
    } catch (error) {
      await this.reschedule(event, error);
      return false;
    }
  }

  private async reschedule(event: ClaimedEvent, error: unknown): Promise<void> {
    const now = new Date();
    const attempts = event.attempts + 1;
    const availableAt = new Date(now.getTime() + outboxBackoffMs(attempts));
    const expired = availableAt >= event.expiresAt;

    await this.database.db
      .update(outboxEvents)
      .set({
        status: expired ? 'dead' : 'pending',
        attempts,
        availableAt,
        lockedUntil: null,
        payload: expired ? null : (event.payload as Record<string, unknown>),
        lastError: this.describeError(error).slice(0, 500),
        updatedAt: now,
      })
      .where(
        and(
          eq(outboxEvents.id, event.id),
          eq(outboxEvents.status, 'processing'),
        ),
      );

    this.logger.warn(
      `Outbox event ${event.id} ${expired ? 'expired' : `scheduled for retry ${attempts}`}`,
    );
  }

  private async expireEvents(eventId?: string): Promise<void> {
    const idFilter = eventId ? sql`AND "id" = ${eventId}` : sql``;
    await this.database.db.execute(sql`
      UPDATE "outbox_events"
      SET
        "status" = 'dead',
        "payload" = NULL,
        "lockedUntil" = NULL,
        "lastError" = 'Event expired before publication',
        "updatedAt" = now()
      WHERE "status" IN ('pending', 'processing')
        AND "expiresAt" <= now()
        ${idFilter}
    `);
  }

  private async markDead(eventId: string, reason: string): Promise<void> {
    await this.database.db
      .update(outboxEvents)
      .set({
        status: 'dead',
        payload: null,
        lockedUntil: null,
        lastError: reason,
        updatedAt: new Date(),
      })
      .where(eq(outboxEvents.id, eventId));
    this.logger.error(`Outbox event ${eventId} moved to dead: ${reason}`);
  }

  private track<T>(promise: Promise<T>): Promise<T> {
    this.inFlight.add(promise);
    void promise.then(
      () => this.inFlight.delete(promise),
      () => this.inFlight.delete(promise),
    );
    return promise;
  }

  private describeError(error: unknown): string {
    return error instanceof Error ? error.message || error.name : String(error);
  }
}
