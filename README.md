# Chatly

Chatly is a pet project for building a chat application.

## 🧱 Tech Stack

- Mobile: Flutter (iOS)
- Backend: NestJS monorepo (`api` and `mail-service`)
- Database: PostgreSQL
- Cache / PubSub: Redis
- Message broker: RabbitMQ
- Storage: MinIO (S3-compatible storage)

---

## 📁 Project Structure

```text
chatly/
  apps/
    mobile/     # Flutter application
    backend/    # NestJS workspace
      apps/
        api/            # HTTP API
        mail-service/   # RabbitMQ consumer
      libs/
        contracts/      # Shared event contracts
  infra/
    docker-compose.yml
```

---

## 🚀 Running Infrastructure (Docker)

This project uses Docker Compose for local development:

- PostgreSQL
- Redis
- RabbitMQ
- MinIO

### ▶️ Start

```bash
docker compose -f infra/docker-compose.yml up -d
```

### ⏹ Stop

```bash
docker compose -f infra/docker-compose.yml down
```

### 🧹 Remove everything (including data)

```bash
docker compose -f infra/docker-compose.yml down -v
```

---

## 🔌 Services Access

| Service     | URL / Host             |
| ----------- | ---------------------- |
| PostgreSQL  | localhost:5432         |
| Redis       | localhost:6379         |
| RabbitMQ    | localhost:5672         |
| RabbitMQ UI | http://localhost:15672 |
| MinIO API   | http://localhost:9000  |
| MinIO UI    | http://localhost:9001  |

### MinIO Credentials

Login: minioadmin
Password: minioadmin

### RabbitMQ Credentials

Login: chatly
Password: chatly

---

## 🧠 Backend (NestJS)

```bash
cd apps/backend
npm install
npm run db:migrate
npm run start:dev               # HTTP API
npm run start:mail-service:dev  # RabbitMQ consumer, in another terminal
```

Default:

http://localhost:3000

---

## 📱 Mobile (Flutter)

```bash
cd apps/mobile
flutter pub get
flutter run

# запуск iPhone 17 Pro
xcrun simctl boot "iPhone 17 Pro"
# запуск iPhone 11
xcrun simctl boot "iPhone 11"
# запуск для использования mcp агентом
flutter run -d "iPhone 17 Pro" --dart-define=ENABLE_FLUTTER_DRIVER=true
```

---

## ⚙️ Environment Variables (example)

Backend (`apps/backend/.env`):

```bash
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=chatly
DATABASE_PASSWORD=chatly
DATABASE_NAME=chatly
JWT_ACCESS_SECRET=replace-me
JWT_ACCESS_EXPIRES_IN=900
JWT_REFRESH_SECRET=replace-me
JWT_REFRESH_EXPIRES_IN=2592000
REDIS_HOST=localhost
REDIS_PORT=6379
RABBITMQ_URL=amqp://chatly:chatly@localhost:5672
MAIL_QUEUE=mail.events
MAIL_DLQ=mail.events.dlq
GMAIL_USER=sender@gmail.com
GMAIL_APP_PASSWORD=replace-with-a-google-app-password
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_AVATARS_BUCKET=chatly-avatars
```

### Database schema

The API uses Drizzle ORM. Schema definitions live in
`apps/backend/apps/api/src/database/schema.ts`, and versioned SQL migrations live in
`apps/backend/drizzle`.

```bash
cd apps/backend
npm run db:generate  # generate SQL after a schema change
npm run db:check     # validate migration metadata
npm run db:migrate   # apply pending migrations
```

The initial Drizzle migration is intended for a clean database. Do not apply it
directly to a database previously created by TypeORM `synchronize`; back up and
baseline that database with `drizzle-kit pull --init` first.

### Mail events

`mail-service` consumes durable messages from `MAIL_QUEUE` using the
`mail.send` pattern. The payload is:

```ts
{
  eventId: string;
  to: string;
  template: string;
  subject?: string;
  context: Record<string, unknown>;
}
```

The supported `google-link` template sends a Google link to the address in
`to`, using `subject` when supplied and `Google` otherwise. Gmail SMTP uses
TLS on port `465` and requires `GMAIL_USER` plus a Google App Password in
`GMAIL_APP_PASSWORD`.

Successful events are acknowledged only after Gmail accepts the message.
Invalid events, unsupported templates, and SMTP errors are rejected without
requeue and routed to `MAIL_DLQ`. Never commit Gmail credentials or paste them
into source files.

---

## 📌 Notes

- Backend and Flutter apps run locally (no Docker) for better development experience
- Docker is used only for infrastructure services
- PostgreSQL and MinIO data persist between container restarts

--
