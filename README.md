# Chatly

Chatly — это pet-проект чат-приложения.

## 🧱 Стек

- Mobile: Flutter (iOS)
- Backend: NestJS
- Database: PostgreSQL
- Cache / PubSub: Redis
- Storage: MinIO (S3-совместимое хранилище)

---

## 📁 Структура проекта

chatly/   apps/     mobile/     # Flutter приложение     backend/    # NestJS API   infra/     docker-compose.yml

---

## 🚀 Запуск инфраструктуры (Docker)

В проекте используется Docker Compose для локального запуска:

- PostgreSQL
- Redis
- MinIO

### ▶️ Запуск

bash docker compose -f infra/docker-compose.yml up -d 

### ⏹ Остановка

bash docker compose -f infra/docker-compose.yml down 

### 🧹 Полное удаление (включая данные)

bash docker compose -f infra/docker-compose.yml down -v 

---

## 🔌 Доступ к сервисам

| Сервис     | URL / Host              |
|------------|-------------------------|
| PostgreSQL | localhost:5432          |
| Redis      | localhost:6379          |
| MinIO API  | http://localhost:9000   |
| MinIO UI   | http://localhost:9001   |

### MinIO доступ

Login:    minioadmin Password: minioadmin

---

## 🧠 Backend (NestJS)

bash cd apps/backend npm install npm run start:dev 

По умолчанию:

http://localhost:3000

---

## 📱 Mobile (Flutter)

bash cd apps/mobile flutter pub get flutter run 

---

## ⚙️ Переменные окружения (пример)

Backend (apps/backend/.env):

DATABASE_URL=postgresql://chatly:chatly@localhost:5432/chatly REDIS_HOST=localhost REDIS_PORT=6379  S3_ENDPOINT=http://localhost:9000 S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin

---

## 📌 Заметки

- Backend и Flutter запускаются локально (без Docker) для удобной разработки
- Docker используется только для инфраструктуры
- Данные PostgreSQL и MinIO сохраняются между перезапусками контейнеров

--