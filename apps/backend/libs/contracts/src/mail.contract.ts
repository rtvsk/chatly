export const MAIL_SEND_PATTERN = 'mail.send';
export const DEFAULT_MAIL_QUEUE = 'mail.events';
export const DEFAULT_MAIL_DLQ = 'mail.events.dlq';

export interface MailSendEvent {
  eventId: string;
  to: string;
  template: string;
  subject?: string;
  context: Record<string, unknown>;
}

const isNonEmptyString = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const isMailSendEvent = (value: unknown): value is MailSendEvent => {
  if (!isRecord(value)) {
    return false;
  }

  return (
    isNonEmptyString(value.eventId) &&
    isNonEmptyString(value.to) &&
    isNonEmptyString(value.template) &&
    (value.subject === undefined || isNonEmptyString(value.subject)) &&
    isRecord(value.context)
  );
};
