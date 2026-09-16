import { connect, type ChannelModel } from 'amqplib';
import { mailRetryQueueName } from '@app/contracts';

export interface RabbitTopologyConfig {
  url: string;
  queue: string;
  deadLetterQueue: string;
  retryDelaysMs: readonly number[];
}

type RabbitConnector = (url: string) => Promise<ChannelModel>;

export async function ensureRabbitTopology(
  config: RabbitTopologyConfig,
  connector: RabbitConnector = connect,
): Promise<void> {
  const connection = await connector(config.url);

  try {
    const channel = await connection.createChannel();

    try {
      await channel.assertQueue(config.deadLetterQueue, { durable: true });
      for (const delayMs of config.retryDelaysMs) {
        await channel.assertQueue(mailRetryQueueName(config.queue, delayMs), {
          durable: true,
          arguments: {
            'x-message-ttl': delayMs,
            'x-dead-letter-exchange': '',
            'x-dead-letter-routing-key': config.queue,
          },
        });
      }
      await channel.assertQueue(config.queue, {
        durable: true,
        arguments: {
          'x-dead-letter-exchange': '',
          'x-dead-letter-routing-key': config.deadLetterQueue,
        },
      });
    } finally {
      await channel.close();
    }
  } finally {
    await connection.close();
  }
}
