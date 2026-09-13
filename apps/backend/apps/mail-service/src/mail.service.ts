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
    const message = this.renderMessage(event);
    const info = await this.mailTransport.transporter.sendMail({
      from: this.mailTransport.from,
      to: event.to,
      ...message,
    });

    this.logger.log(
      `Sent mail event ${event.eventId} as message ${info.messageId}`,
    );
  }

  private renderMessage(event: MailSendEvent) {
    if (event.template === 'google-link') {
      const url = 'https://www.google.com';

      return {
        subject: event.subject ?? 'Google',
        text: url,
        html: `<p>Перейти на Google:</p><a href="${url}">${url}</a>`,
      };
    }

    if (event.template === 'email-verification') {
      const url = event.context.verificationUrl;
      const safeUrl = this.escapeHtml(url);

      return {
        subject: event.subject ?? 'Confirm your Chatly email',
        text: `Confirm your email address: ${url}`,
        html: `<p>Confirm your email address:</p><p><a href="${safeUrl}">Confirm email</a></p>`,
      };
    }

    throw new Error(
      `Unsupported mail template: ${(event as { template: string }).template}`,
    );
  }

  private escapeHtml(value: string): string {
    return value.replace(/[&<>'"]/g, (character) => {
      const entities: Record<string, string> = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        "'": '&#39;',
        '"': '&quot;',
      };

      return entities[character];
    });
  }

  onModuleDestroy(): void {
    this.mailTransport.transporter.close();
  }
}
