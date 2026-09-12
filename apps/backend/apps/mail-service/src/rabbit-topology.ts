import { connect, type ChannelModel } from 'amqplib';

export interface RabbitTopologyConfig {
  url: string;
  queue: string;
  deadLetterQueue: string;
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
