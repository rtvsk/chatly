# Chatly

Chatly is a pet project for building a chat application.

## 🧱 Tech Stack

- Mobile: Flutter (iOS)
- Backend: NestJS
- Database: PostgreSQL
- Cache / PubSub: Redis
- Storage: MinIO (S3-compatible storage)

---

## 📁 Project Structure

```text
chatly/
  apps/
    mobile/     # Flutter application
    backend/    # NestJS API
  infra/
    docker-compose.yml
```

---

## 🚀 Running Infrastructure (Docker)

This project uses Docker Compose for local development:

- PostgreSQL
- Redis
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

| Service    | URL / Host              |
|------------|-------------------------|
| PostgreSQL | localhost:5432          |
| Redis      | localhost:6379          |
| MinIO API  | http://localhost:9000   |
| MinIO UI   | http://localhost:9001   |

### MinIO Credentials

Login:    minioadmin
Password: minioadmin

---

## 🧠 Backend (NestJS)

```bash
cd apps/backend
npm install
npm run db:migrate
npm run start:dev
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
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_AVATARS_BUCKET=chatly-avatars
```

### Database schema

The backend uses Drizzle ORM. Schema definitions live in
`apps/backend/src/database/schema.ts`, and versioned SQL migrations live in
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

---

## 📌 Notes

- Backend and Flutter apps run locally (no Docker) for better development experience
- Docker is used only for infrastructure services
- PostgreSQL and MinIO data persist between container restarts

--
