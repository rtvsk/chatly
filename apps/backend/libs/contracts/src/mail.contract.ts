export const MAIL_SEND_PATTERN = 'mail.send';
export const DEFAULT_MAIL_QUEUE = 'mail.events';
export const DEFAULT_MAIL_DLQ = 'mail.events.dlq';

export interface GoogleLinkMailSendEvent {
  eventId: string;
  to: string;
  template: 'google-link';
  subject?: string;
  context: Record<string, unknown>;
}

export interface EmailVerificationMailSendEvent {
  eventId: string;
  to: string;
  template: 'email-verification';
  subject?: string;
  context: {
    verificationUrl: string;
  };
}

export type MailSendEvent =
  | GoogleLinkMailSendEvent
  | EmailVerificationMailSendEvent;

const isNonEmptyString = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const isMailSendEvent = (value: unknown): value is MailSendEvent => {
  if (!isRecord(value)) {
    return false;
  }

  if (
    !isNonEmptyString(value.eventId) ||
    !isNonEmptyString(value.to) ||
    (value.subject !== undefined && !isNonEmptyString(value.subject)) ||
    !isRecord(value.context)
  ) {
    return false;
  }

  if (value.template === 'google-link') {
    return true;
  }

  return (
    value.template === 'email-verification' &&
    isNonEmptyString(value.context.verificationUrl)
  );
};
