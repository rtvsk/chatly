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
      },
      () => Promise.resolve(connection),
    );

    expect(assertQueue).toHaveBeenNthCalledWith(1, 'mail.events.dlq', {
      durable: true,
    });
    expect(assertQueue).toHaveBeenNthCalledWith(2, 'mail.events', {
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
