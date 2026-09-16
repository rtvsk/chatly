import { Controller, Logger } from '@nestjs/common';
import { Ctx, EventPattern, Payload, RmqContext } from '@nestjs/microservices';
import type { ConsumeMessage, Options } from 'amqplib';
import {
  DEFAULT_MAIL_QUEUE,
  isMailSendEvent,
  MAIL_RETRY_DELAYS_MS,
  MAIL_RETRY_HEADER,
  MAIL_SEND_PATTERN,
  mailRetryQueueName,
} from '@app/contracts';

import { MailService } from './mail.service';

interface RetryChannel {
  ack(message: ConsumeMessage): void;
  nack(message: ConsumeMessage, allUpTo?: boolean, requeue?: boolean): void;
  sendToQueue(
    queue: string,
    content: Buffer,
    options?: Options.Publish,
  ): Promise<boolean>;
}

@Controller()
export class MailEventsController {
  private readonly logger = new Logger(MailEventsController.name);

  constructor(private readonly mailService: MailService) {}

  @EventPattern(MAIL_SEND_PATTERN)
  async handleMailSend(
    @Payload() payload: unknown,
    @Ctx() context: RmqContext,
  ): Promise<void> {
    const channel = context.getChannelRef() as RetryChannel;
    const message = context.getMessage() as ConsumeMessage;

    if (!isMailSendEvent(payload)) {
      this.logger.error('Rejected invalid mail.send event');
      channel.nack(message, false, false);
      return;
    }

    if (
      payload.template === 'email-verification' &&
      Date.parse(payload.expiresAt) <= Date.now()
    ) {
      this.logger.error(`Rejected expired mail event ${payload.eventId}`);
      channel.nack(message, false, false);
      return;
    }

    try {
      await this.mailService.process(payload);
      channel.ack(message);
    } catch {
      const attempt = this.retryAttempt(message);
      if (attempt >= MAIL_RETRY_DELAYS_MS.length) {
        this.logger.error(
          `Mail event ${payload.eventId} exhausted ${attempt} retries`,
        );
        channel.nack(message, false, false);
        return;
      }

      const nextAttempt = attempt + 1;
      const retryQueue = mailRetryQueueName(
        process.env.MAIL_QUEUE ?? DEFAULT_MAIL_QUEUE,
        MAIL_RETRY_DELAYS_MS[attempt],
      );

      try {
        await channel.sendToQueue(retryQueue, message.content, {
          persistent: true,
          headers: {
            ...this.headers(message),
            [MAIL_RETRY_HEADER]: nextAttempt,
          },
        });
        channel.ack(message);
        this.logger.warn(
          `Mail event ${payload.eventId} scheduled for retry ${nextAttempt}`,
        );
      } catch {
        this.logger.error(
          `Unable to schedule retry ${nextAttempt} for mail event ${payload.eventId}`,
        );
        channel.nack(message, false, true);
      }
    }
  }

  private retryAttempt(message: ConsumeMessage): number {
    const value = this.headers(message)[MAIL_RETRY_HEADER];
    return typeof value === 'number' &&
      Number.isSafeInteger(value) &&
      value >= 0
      ? value
      : 0;
  }

  private headers(message: ConsumeMessage): Record<string, unknown> {
    const headers: unknown = message.properties.headers;
    return typeof headers === 'object' && headers !== null
      ? (headers as Record<string, unknown>)
      : {};
  }
}
