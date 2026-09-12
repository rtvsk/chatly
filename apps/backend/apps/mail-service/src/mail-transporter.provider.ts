import type { Provider } from '@nestjs/common';
import { createTransport, type Transporter } from 'nodemailer';
import type SMTPTransport from 'nodemailer/lib/smtp-transport';

export const MAIL_TRANSPORT = Symbol('MAIL_TRANSPORT');

export interface MailTransport {
  from: string;
  transporter: Transporter<SMTPTransport.SentMessageInfo>;
}

const requiredEnvironmentVariable = (name: string): string => {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
};

export const mailTransportProvider: Provider<MailTransport> = {
  provide: MAIL_TRANSPORT,
  useFactory: () => {
    const user = requiredEnvironmentVariable('GMAIL_USER');
    const password = requiredEnvironmentVariable('GMAIL_APP_PASSWORD');

    return {
      from: user,
      transporter: createTransport({
        pool: true,
        host: 'smtp.gmail.com',
        port: 465,
        secure: true,
        auth: {
          user,
          pass: password,
        },
      }),
    };
  },
};
