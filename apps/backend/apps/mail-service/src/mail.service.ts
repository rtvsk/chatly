import { Injectable, Logger } from '@nestjs/common';
import type { MailSendEvent } from '@app/contracts';

@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);

  process(event: MailSendEvent): Promise<void> {
    this.logger.log(
      `Processing mail event ${event.eventId} with template ${event.template}`,
    );
    return Promise.resolve();
  }
}
