import { Controller, Logger } from '@nestjs/common';
import { Ctx, EventPattern, Payload, RmqContext } from '@nestjs/microservices';
import type { Channel, ConsumeMessage } from 'amqplib';
import { isMailSendEvent, MAIL_SEND_PATTERN } from '@app/contracts';

import { MailService } from './mail.service';

@Controller()
export class MailEventsController {
  private readonly logger = new Logger(MailEventsController.name);

  constructor(private readonly mailService: MailService) {}

  @EventPattern(MAIL_SEND_PATTERN)
  async handleMailSend(
    @Payload() payload: unknown,
    @Ctx() context: RmqContext,
  ): Promise<void> {
    const channel = context.getChannelRef() as Channel;
    const message = context.getMessage() as ConsumeMessage;

    if (!isMailSendEvent(payload)) {
      this.logger.error('Rejected invalid mail.send event');
      channel.nack(message, false, false);
      return;
    }

    try {
      await this.mailService.process(payload);
      channel.ack(message);
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'Unknown error';
      this.logger.error(
        `Failed to process mail event ${payload.eventId}: ${reason}`,
      );
      channel.nack(message, false, false);
    }
  }
}
