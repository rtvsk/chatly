# Chatly backend

This directory is a NestJS monorepo with two runnable applications and one
shared library:

- `apps/api`: existing HTTP API;
- `apps/mail-service`: RabbitMQ mail-event consumer;
- `libs/contracts`: shared message patterns, queue defaults, and payload types.

## Setup

```bash
npm install
```

Create `apps/backend/.env` using the environment example in the root README,
then start the local infrastructure from the repository root.

## Run

```bash
npm run start:dev               # HTTP API with watch mode
npm run start:mail-service:dev  # mail consumer with watch mode
```

The compatibility commands `start`, `start:dev`, `start:debug`, and
`start:prod` continue to target the API.

## Build and test

```bash
npm run build
npm test -- --runInBand
npm run test:e2e -- --runInBand
npm run db:check
```

`npm run build` builds every Nest project. Use `build:api` or
`build:mail-service` for a focused build.

## RabbitMQ mail contract

The mail consumer listens to `mail.send` messages on `MAIL_QUEUE` (default
`mail.events`). Its payload is:

```ts
interface MailSendEvent {
  eventId: string;
  to: string;
  template: string;
  expiresAt?: string; // Required for email-verification events.
  subject?: string;
  context: Record<string, unknown>;
}
```

The consumer declares the durable main queue, retry queues with delays of 10
seconds, 1 minute, and 5 minutes, and `MAIL_DLQ` (default `mail.events.dlq`).
Messages are manually acknowledged after successful SMTP delivery. Temporary
SMTP failures pass through the retry queues. Invalid, expired, and exhausted
events are routed to the final DLQ.

Supported templates are `google-link` and `email-verification`. The latter
requires `context.verificationUrl` and sends a confirmation link to the event's
`to` address.

The API publishes `email-verification` events after signup. Set this required
public API URL (the API appends the opaque token as its `token` query parameter):

```bash
EMAIL_VERIFICATION_BASE_URL=http://localhost:3000/auth/verify-email
```

Configure Gmail with environment variables; never commit their values:

```bash
GMAIL_USER=sender@gmail.com
GMAIL_APP_PASSWORD=replace-with-a-google-app-password
```

The Gmail account must have 2-Step Verification enabled, and the password must
be a dedicated Google App Password rather than the account password.

Signup and resend write verification events to `outbox_events` in the same
database transaction as their user/token changes. The API attempts immediate
delivery and also polls pending events once per second.

The final DLQ is not consumed automatically. Redrive a specific event or a
bounded batch only after fixing the underlying problem:

```bash
npm run mail:dlq:redrive -- --event-id EVENT_UUID
npm run mail:dlq:redrive -- --limit 10
```

Expired verification events stay quarantined by default. Remove them only with
the explicit `--discard-expired` option; users need a new link through the
resend-verification endpoint.
