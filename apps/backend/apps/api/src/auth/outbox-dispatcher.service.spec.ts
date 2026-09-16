import type { MailSendEvent } from '@app/contracts';

import { DatabaseService } from '../database/database.service';
import { MailPublisher } from './mail.publisher';
import {
  outboxBackoffMs,
  OutboxDispatcherService,
} from './outbox-dispatcher.service';

const event: MailSendEvent = {
  eventId: 'event-1',
  to: 'recipient@example.com',
  template: 'email-verification',
  expiresAt: new Date(Date.now() + 60_000).toISOString(),
  context: { verificationUrl: 'https://chatly.test/verify?token=opaque' },
};

describe('OutboxDispatcherService', () => {
  it('uses capped exponential backoff with bounded jitter', () => {
    expect(outboxBackoffMs(1, () => 0.5)).toBe(1_000);
    expect(outboxBackoffMs(2, () => 0.5)).toBe(5_000);
    expect(outboxBackoffMs(5, () => 0.5)).toBe(300_000);
    expect(outboxBackoffMs(20, () => 0.5)).toBe(300_000);
    expect(outboxBackoffMs(1, () => 0)).toBe(800);
    expect(outboxBackoffMs(1, () => 1)).toBe(1_200);
  });

  it('publishes a claimed event and clears its sensitive payload', async () => {
    const execute = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: event.eventId,
            topic: 'mail.send',
            payload: event,
            attempts: 0,
            expiresAt: new Date(Date.now() + 60_000),
          },
        ],
      });
    const where = jest.fn().mockResolvedValue(undefined);
    const set = jest.fn(() => ({ where }));
    const database = {
      db: { execute, update: jest.fn(() => ({ set })) },
    } as unknown as DatabaseService;
    const publish = jest.fn().mockResolvedValue(undefined);
    const publisher = { publish } as unknown as MailPublisher;
    const service = new OutboxDispatcherService(database, publisher);

    await expect(service.dispatchNow(event.eventId)).resolves.toBe(true);

    expect(publish).toHaveBeenCalledWith(event);
    expect(set).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'published', payload: null }),
    );
  });

  it('retains the payload and schedules a retry after publication fails', async () => {
    const expiresAt = new Date(Date.now() + 60_000);
    const execute = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: event.eventId,
            topic: 'mail.send',
            payload: event,
            attempts: 0,
            expiresAt,
          },
        ],
      });
    const where = jest.fn().mockResolvedValue(undefined);
    const set = jest.fn(() => ({ where }));
    const database = {
      db: { execute, update: jest.fn(() => ({ set })) },
    } as unknown as DatabaseService;
    const publisher = {
      publish: jest.fn().mockRejectedValue(new Error('rabbit unavailable')),
    } as unknown as MailPublisher;
    const service = new OutboxDispatcherService(database, publisher);

    await expect(service.dispatchNow(event.eventId)).resolves.toBe(false);

    const setCalls = set.mock.calls as unknown as [
      [
        {
          status: string;
          attempts: number;
          payload: unknown;
          availableAt: Date;
        },
      ],
    ];
    expect(setCalls[0][0]).toMatchObject({
      status: 'pending',
      attempts: 1,
      payload: event,
    });
    expect(setCalls[0][0].availableAt.getTime()).toBeLessThan(
      expiresAt.getTime(),
    );
  });

  it('does not start overlapping polling cycles', async () => {
    let releaseExpiry: (() => void) | undefined;
    const expiry = new Promise<void>((resolve) => {
      releaseExpiry = resolve;
    });
    const database = {} as DatabaseService;
    const service = new OutboxDispatcherService(database, {} as MailPublisher);
    const internals = service as unknown as {
      startPoll(): void;
      expireEvents: jest.Mock;
      claimEvents: jest.Mock;
    };
    internals.expireEvents = jest.fn(() => expiry);
    internals.claimEvents = jest.fn().mockResolvedValue([]);

    internals.startPoll();
    internals.startPoll();

    expect(internals.expireEvents).toHaveBeenCalledTimes(1);
    releaseExpiry?.();
    await service.onApplicationShutdown();
    expect(internals.claimEvents).toHaveBeenCalledTimes(1);
  });
});
