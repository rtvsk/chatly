import type { Channel, ChannelModel } from 'amqplib';

import { ensureRabbitTopology } from './rabbit-topology';

describe('ensureRabbitTopology', () => {
  it('declares durable mail and dead-letter queues', async () => {
    const assertQueue = jest.fn().mockResolvedValue({});
    const closeChannel = jest.fn().mockResolvedValue(undefined);
    const closeConnection = jest.fn().mockResolvedValue(undefined);
    const channel = {
      assertQueue,
      close: closeChannel,
    } as unknown as Channel;
    const connection = {
      createChannel: jest.fn().mockResolvedValue(channel),
      close: closeConnection,
    } as unknown as ChannelModel;

    await ensureRabbitTopology(
      {
        url: 'amqp://localhost',
        queue: 'mail.events',
        deadLetterQueue: 'mail.events.dlq',
        retryDelaysMs: [10_000, 60_000, 300_000],
      },
      () => Promise.resolve(connection),
    );

    expect(assertQueue).toHaveBeenNthCalledWith(1, 'mail.events.dlq', {
      durable: true,
    });
    expect(assertQueue).toHaveBeenNthCalledWith(2, 'mail.events.retry.10000', {
      durable: true,
      arguments: {
        'x-message-ttl': 10_000,
        'x-dead-letter-exchange': '',
        'x-dead-letter-routing-key': 'mail.events',
      },
    });
    expect(assertQueue).toHaveBeenNthCalledWith(
      3,
      'mail.events.retry.60000',
      expect.any(Object),
    );
    expect(assertQueue).toHaveBeenNthCalledWith(
      4,
      'mail.events.retry.300000',
      expect.any(Object),
    );
    expect(assertQueue).toHaveBeenNthCalledWith(5, 'mail.events', {
      durable: true,
      arguments: {
        'x-dead-letter-exchange': '',
        'x-dead-letter-routing-key': 'mail.events.dlq',
      },
    });
    expect(closeChannel).toHaveBeenCalled();
    expect(closeConnection).toHaveBeenCalled();
  });
});
