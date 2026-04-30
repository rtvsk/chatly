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

 chatly/   apps/     mobile/     # Flutter application     backend/    # NestJS API   infra/     docker-compose.yml

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

Login:    minioadmin Password: minioadmin

---

## 🧠 Backend (NestJS)

```bash
cd apps/backend npm install npm run start:dev
```

Default:

http://localhost:3000

---

## 📱 Mobile (Flutter)

```bash
cd apps/mobile flutter pub get flutter run
```

---

## ⚙️ Environment Variables (example)

Backend (apps/backend/.env):

```bash
DATABASE_URL=postgresql://chatly:chatly@localhost:5432/chatly
REDIS_HOST=localhost
REDIS_PORT=6379
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
```

---

## 📌 Notes

- Backend and Flutter apps run locally (no Docker) for better development experience
- Docker is used only for infrastructure services
- PostgreSQL and MinIO data persist between container restarts

--