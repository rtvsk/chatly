import 'dotenv/config';

import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import {
  MicroserviceOptions,
  RmqOptions,
  Transport,
} from '@nestjs/microservices';
import { DEFAULT_MAIL_DLQ, DEFAULT_MAIL_QUEUE } from '@app/contracts';

import { MailServiceModule } from './mail-service.module';
import { ensureRabbitTopology } from './rabbit-topology';

const requiredEnvironmentVariable = (name: string): string => {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
};

const describeError = (error: unknown): string => {
  if (error instanceof AggregateError) {
    return error.errors.map(describeError).join('; ');
  }

  if (error instanceof Error) {
    return error.message || error.name;
  }

  return String(error);
};

async function bootstrap(): Promise<void> {
  const url = requiredEnvironmentVariable('RABBITMQ_URL');
  const queue = process.env.MAIL_QUEUE ?? DEFAULT_MAIL_QUEUE;
  const deadLetterQueue = process.env.MAIL_DLQ ?? DEFAULT_MAIL_DLQ;
  const queueOptions: NonNullable<
    NonNullable<RmqOptions['options']>['queueOptions']
  > = {
    durable: true,
    arguments: {
      'x-dead-letter-exchange': '',
      'x-dead-letter-routing-key': deadLetterQueue,
    },
  };

  await ensureRabbitTopology({ url, queue, deadLetterQueue });

  const app = await NestFactory.createMicroservice<MicroserviceOptions>(
    MailServiceModule,
    {
      transport: Transport.RMQ,
      options: {
        urls: [url],
        queue,
        noAck: false,
        queueOptions,
      },
    },
  );

  await app.listen();
}

void bootstrap().catch((error: unknown) => {
  Logger.error(
    `Mail service failed to start: ${describeError(error)}`,
    'Bootstrap',
  );
  process.exitCode = 1;
});
