import { Inject, Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import type { MailSendEvent } from '@app/contracts';

import {
  MAIL_TRANSPORT,
  type MailTransport,
} from './mail-transporter.provider';

@Injectable()
export class MailService implements OnModuleDestroy {
  private readonly logger = new Logger(MailService.name);

  constructor(
    @Inject(MAIL_TRANSPORT) private readonly mailTransport: MailTransport,
  ) {}

  async process(event: MailSendEvent): Promise<void> {
    if (event.template !== 'google-link') {
      throw new Error(`Unsupported mail template: ${event.template}`);
    }

    const url = 'https://www.google.com';
    const info = await this.mailTransport.transporter.sendMail({
      from: this.mailTransport.from,
      to: event.to,
      subject: event.subject ?? 'Google',
      text: url,
      html: `<p>Перейти на Google:</p><a href="${url}">${url}</a>`,
    });

    this.logger.log(
      `Sent mail event ${event.eventId} as message ${info.messageId}`,
    );
  }

  onModuleDestroy(): void {
    this.mailTransport.transporter.close();
  }
}
