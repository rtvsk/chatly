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
  subject?: string;
  context: Record<string, unknown>;
}
```

The consumer declares both the durable main queue and `MAIL_DLQ` (default
`mail.events.dlq`). Messages are manually acknowledged after successful SMTP
delivery. Invalid messages, unsupported templates, and SMTP failures are
rejected without requeue and routed to the DLQ.

The currently supported template is `google-link`. It sends a Google link to
the event's `to` address and uses the optional event subject or `Google` by
default.

Configure Gmail with environment variables; never commit their values:

```bash
GMAIL_USER=sender@gmail.com
GMAIL_APP_PASSWORD=replace-with-a-google-app-password
```

The Gmail account must have 2-Step Verification enabled, and the password must
be a dedicated Google App Password rather than the account password.
