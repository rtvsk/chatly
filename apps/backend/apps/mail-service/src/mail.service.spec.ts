import type { Transporter } from 'nodemailer';
import type SMTPTransport from 'nodemailer/lib/smtp-transport';
import type { MailSendEvent } from '@app/contracts';

import type { MailTransport } from './mail-transporter.provider';
import { MailService } from './mail.service';

describe('MailService', () => {
  const event: MailSendEvent = {
    eventId: 'event-1',
    to: 'recipient@example.com',
    template: 'google-link',
    context: {},
  };

  let sendMail: jest.Mock;
  let close: jest.Mock;
  let service: MailService;

  beforeEach(() => {
    sendMail = jest.fn().mockResolvedValue({ messageId: 'message-1' });
    close = jest.fn();
    const mailTransport: MailTransport = {
      from: 'sender@example.com',
      transporter: {
        sendMail,
        close,
      } as unknown as Transporter<SMTPTransport.SentMessageInfo>,
    };
    service = new MailService(mailTransport);
  });

  it('sends the google-link template to the event recipient', async () => {
    await service.process(event);

    expect(sendMail).toHaveBeenCalledWith({
      from: 'sender@example.com',
      to: 'recipient@example.com',
      subject: 'Google',
      text: 'https://www.google.com',
      html: '<p>Перейти на Google:</p><a href="https://www.google.com">https://www.google.com</a>',
    });
  });

  it('uses a subject supplied by the event', async () => {
    await service.process({ ...event, subject: 'Open Google' });

    expect(sendMail).toHaveBeenCalledWith(
      expect.objectContaining({ subject: 'Open Google' }),
    );
  });

  it('sends an email verification link with a safe HTML href', async () => {
    await service.process({
      eventId: 'event-2',
      to: 'recipient@example.com',
      template: 'email-verification',
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      context: {
        verificationUrl: 'https://chatly.test/auth/verify-email?token=abc',
      },
    });

    expect(sendMail).toHaveBeenCalledWith({
      from: 'sender@example.com',
      to: 'recipient@example.com',
      subject: 'Confirm your Chatly email',
      text: 'Confirm your email address: https://chatly.test/auth/verify-email?token=abc',
      html: '<p>Confirm your email address:</p><p><a href="https://chatly.test/auth/verify-email?token=abc">Confirm email</a></p>',
    });
  });

  it('rejects unsupported templates without sending mail', async () => {
    await expect(
      service.process({ ...event, template: 'unknown' } as never),
    ).rejects.toThrow('Unsupported mail template: unknown');
    expect(sendMail).not.toHaveBeenCalled();
  });

  it('closes the pooled SMTP transport on shutdown', () => {
    service.onModuleDestroy();

    expect(close).toHaveBeenCalled();
  });
});
