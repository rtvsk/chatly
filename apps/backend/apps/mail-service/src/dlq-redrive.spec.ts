import type {
  ChannelModel,
  ConfirmChannel,
  GetMessage,
  Options,
} from 'amqplib';
import {
  MAIL_REDRIVE_HEADER,
  MAIL_RETRY_HEADER,
  MAIL_SEND_PATTERN,
  type MailSendEvent,
} from '@app/contracts';

import { parseArguments, redriveDlq } from './dlq-redrive';

const event = (expiresAt = new Date(Date.now() + 60_000).toISOString()) =>
  ({
    eventId: 'event-1',
    to: 'recipient@example.com',
    template: 'email-verification',
    expiresAt,
    context: { verificationUrl: 'https://chatly.test/verify?token=opaque' },
  }) satisfies MailSendEvent;

const message = (payload: MailSendEvent): GetMessage =>
  ({
    content: Buffer.from(
      JSON.stringify({ pattern: MAIL_SEND_PATTERN, data: payload }),
    ),
    properties: { headers: { [MAIL_REDRIVE_HEADER]: 1 } },
  }) as GetMessage;

const setup = (mail: GetMessage) => {
  const ack = jest.fn();
  const nack = jest.fn();
  const sendToQueue = jest
    .fn<
      (queue: string, content: Buffer, options?: Options.Publish) => boolean
    >()
    .mockReturnValue(true);
  const waitForConfirms = jest.fn().mockResolvedValue(undefined);
  const closeChannel = jest.fn().mockResolvedValue(undefined);
  const channel = {
    checkQueue: jest
      .fn()
      .mockResolvedValueOnce({ messageCount: 1 })
      .mockResolvedValueOnce({ messageCount: 0 }),
    get: jest.fn().mockResolvedValueOnce(mail),
    ack,
    nack,
    sendToQueue,
    waitForConfirms,
    close: closeChannel,
  } as unknown as ConfirmChannel;
  const closeConnection = jest.fn().mockResolvedValue(undefined);
  const connection = {
    createConfirmChannel: jest.fn().mockResolvedValue(channel),
    close: closeConnection,
  } as unknown as ChannelModel;

  return {
    ack,
    nack,
    sendToQueue,
    waitForConfirms,
    connector: jest.fn().mockResolvedValue(connection),
  };
};

describe('DLQ redrive', () => {
  it('requires an event id or a bounded limit', () => {
    expect(() => parseArguments([])).toThrow(
      'Either --event-id or --limit is required',
    );
    expect(parseArguments(['--limit', '5'])).toEqual({
      limit: 5,
      eventId: undefined,
      discardExpired: false,
    });
  });

  it('confirms republishing before acknowledging the DLQ message', async () => {
    const mail = message(event());
    const mocks = setup(mail);

    await expect(
      redriveDlq(
        { limit: 1, discardExpired: false },
        {
          url: 'amqp://test',
          queue: 'mail.events',
          deadLetterQueue: 'mail.events.dlq',
        },
        mocks.connector,
      ),
    ).resolves.toEqual({ scanned: 1, redriven: 1, discardedExpired: 0 });

    const [queue, content, options] = mocks.sendToQueue.mock
      .calls[0] as unknown as [string, Buffer, Options.Publish | undefined];
    expect(queue).toBe('mail.events');
    expect(content).toBe(mail.content);
    expect(options?.persistent).toBe(true);
    expect(options?.headers).toMatchObject({
      [MAIL_RETRY_HEADER]: 0,
      [MAIL_REDRIVE_HEADER]: 2,
    });
    expect(mocks.waitForConfirms.mock.invocationCallOrder[0]).toBeLessThan(
      mocks.ack.mock.invocationCallOrder[0],
    );
  });

  it('leaves a message unacked when publisher confirmation fails', async () => {
    const mail = message(event());
    const mocks = setup(mail);
    mocks.waitForConfirms.mockRejectedValue(new Error('not confirmed'));

    await expect(
      redriveDlq(
        { eventId: 'event-1', discardExpired: false },
        {
          url: 'amqp://test',
          queue: 'mail.events',
          deadLetterQueue: 'mail.events.dlq',
        },
        mocks.connector,
      ),
    ).rejects.toThrow('not confirmed');
    expect(mocks.ack).not.toHaveBeenCalled();
  });

  it('keeps expired verification events unless discard is explicit', async () => {
    const mail = message(event(new Date(Date.now() - 1).toISOString()));
    const mocks = setup(mail);

    await redriveDlq(
      { limit: 1, discardExpired: false },
      {
        url: 'amqp://test',
        queue: 'mail.events',
        deadLetterQueue: 'mail.events.dlq',
      },
      mocks.connector,
    );

    expect(mocks.sendToQueue).not.toHaveBeenCalled();
    expect(mocks.ack).not.toHaveBeenCalled();
    expect(mocks.nack).toHaveBeenCalledWith(mail, false, true);
  });

  it('discards an expired event only when explicitly requested', async () => {
    const mail = message(event(new Date(Date.now() - 1).toISOString()));
    const mocks = setup(mail);

    await expect(
      redriveDlq(
        { eventId: 'event-1', discardExpired: true },
        {
          url: 'amqp://test',
          queue: 'mail.events',
          deadLetterQueue: 'mail.events.dlq',
        },
        mocks.connector,
      ),
    ).resolves.toEqual({ scanned: 1, redriven: 0, discardedExpired: 1 });

    expect(mocks.ack).toHaveBeenCalledWith(mail);
    expect(mocks.nack).not.toHaveBeenCalled();
  });
});
