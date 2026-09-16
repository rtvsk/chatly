import 'dotenv/config';

import {
  connect,
  type ChannelModel,
  type GetMessage,
  type Options,
} from 'amqplib';
import {
  DEFAULT_MAIL_DLQ,
  DEFAULT_MAIL_QUEUE,
  isMailSendEvent,
  MAIL_REDRIVE_HEADER,
  MAIL_RETRY_HEADER,
  type MailSendEvent,
} from '@app/contracts';

export interface RedriveArguments {
  eventId?: string;
  limit?: number;
  discardExpired: boolean;
}

interface NestEventPacket {
  pattern?: unknown;
  data?: unknown;
}

const requiredEnvironmentVariable = (name: string): string => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
};

export interface RedriveResult {
  scanned: number;
  redriven: number;
  discardedExpired: number;
}

const optionValue = (argv: string[], name: string): string | undefined => {
  const exactIndex = argv.indexOf(name);
  if (exactIndex >= 0) {
    return argv[exactIndex + 1];
  }

  return argv
    .find((argument) => argument.startsWith(`${name}=`))
    ?.slice(name.length + 1);
};

export const parseArguments = (argv: string[]): RedriveArguments => {
  const eventId = optionValue(argv, '--event-id');
  const limitValue = optionValue(argv, '--limit');
  const limit = limitValue === undefined ? undefined : Number(limitValue);

  if (!eventId && limit === undefined) {
    throw new Error('Either --event-id or --limit is required');
  }
  if (
    limit !== undefined &&
    (!Number.isSafeInteger(limit) || limit < 1 || limit > 100)
  ) {
    throw new Error('--limit must be an integer between 1 and 100');
  }

  return {
    eventId,
    limit,
    discardExpired: argv.includes('--discard-expired'),
  };
};

const decodeEvent = (message: GetMessage): MailSendEvent | undefined => {
  try {
    const packet = JSON.parse(message.content.toString()) as NestEventPacket;
    return isMailSendEvent(packet.data) ? packet.data : undefined;
  } catch {
    return undefined;
  }
};

const numericHeader = (value: unknown): number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
    ? value
    : 0;

const messageHeaders = (message: GetMessage): Record<string, unknown> => {
  const headers: unknown = message.properties.headers;
  return typeof headers === 'object' && headers !== null
    ? (headers as Record<string, unknown>)
    : {};
};

const publishOptions = (message: GetMessage): Options.Publish => ({
  persistent: true,
  headers: {
    ...messageHeaders(message),
    [MAIL_RETRY_HEADER]: 0,
    [MAIL_REDRIVE_HEADER]:
      numericHeader(messageHeaders(message)[MAIL_REDRIVE_HEADER]) + 1,
  },
});

export async function redriveDlq(
  args: RedriveArguments,
  config: { url: string; queue: string; deadLetterQueue: string },
  connector: (url: string) => Promise<ChannelModel> = connect,
): Promise<RedriveResult> {
  const connection = await connector(config.url);
  const channel = await connection.createConfirmChannel();
  const held: GetMessage[] = [];
  let scanned = 0;
  let redriven = 0;
  let discardedExpired = 0;

  try {
    const queueState = await channel.checkQueue(config.deadLetterQueue);
    await channel.checkQueue(config.queue);
    const scanLimit = queueState.messageCount;

    while (
      scanned < scanLimit &&
      redriven < (args.eventId ? 1 : (args.limit ?? 0))
    ) {
      const message = await channel.get(config.deadLetterQueue, {
        noAck: false,
      });
      if (!message) {
        break;
      }
      scanned += 1;

      const event = decodeEvent(message);
      if (!event || (args.eventId && event.eventId !== args.eventId)) {
        held.push(message);
        continue;
      }

      const expired =
        event.template === 'email-verification' &&
        Date.parse(event.expiresAt) <= Date.now();
      if (expired) {
        if (args.discardExpired) {
          channel.ack(message);
          discardedExpired += 1;
        } else {
          held.push(message);
        }
        continue;
      }

      channel.sendToQueue(
        config.queue,
        message.content,
        publishOptions(message),
      );
      await channel.waitForConfirms();
      channel.ack(message);
      redriven += 1;
      console.log(`Redriven mail event ${event.eventId}`);
    }

    for (const message of held) {
      channel.nack(message, false, true);
    }

    console.log(
      `DLQ redrive complete: scanned=${scanned} redriven=${redriven} discardedExpired=${discardedExpired}`,
    );
    return { scanned, redriven, discardedExpired };
  } finally {
    await channel.close();
    await connection.close();
  }
}

async function main(): Promise<void> {
  const args = parseArguments(process.argv.slice(2));
  await redriveDlq(args, {
    url: requiredEnvironmentVariable('RABBITMQ_URL'),
    queue: process.env.MAIL_QUEUE ?? DEFAULT_MAIL_QUEUE,
    deadLetterQueue: process.env.MAIL_DLQ ?? DEFAULT_MAIL_DLQ,
  });
}

if (require.main === module) {
  void main().catch((error: unknown) => {
    const reason = error instanceof Error ? error.message : String(error);
    console.error(`DLQ redrive failed: ${reason}`);
    process.exitCode = 1;
  });
}
