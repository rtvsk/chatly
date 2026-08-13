# AGENTS.md

## Scope

These instructions apply to the entire repository. More specific `AGENTS.md`
files may override them for their subdirectories.

## Repository overview

Chatly is a small monorepo:

- `apps/backend`: NestJS 11 API written in TypeScript, using Drizzle ORM and PostgreSQL.
- `apps/mobile`: Flutter client written in Dart. Product code lives under `lib/`.
- `infra/docker-compose.yml`: local PostgreSQL, Redis, and MinIO services.

Run app-specific commands from the corresponding app directory. There is no
root package manager or root-level test command.

## Code discovery

This repository uses `codebase-memory-mcp`. Prefer the knowledge graph for
discovering code and relationships:

1. `search_graph` for functions, classes, routes, and variables.
2. `trace_path` for callers and callees.
3. `get_code_snippet` for a specific symbol after locating its qualified name.
4. `query_graph` for complex relationships.
5. `get_architecture` for a high-level overview.

If the repository is not indexed, run `index_repository` first. Fall back to
`rg` for string literals, configuration, documentation, generated files, or
when graph results are insufficient.

## Development commands

Infrastructure, from the repository root:

```bash
docker compose -f infra/docker-compose.yml up -d
docker compose -f infra/docker-compose.yml down
```

Do not run `docker compose ... down -v` unless the user explicitly asks to
delete local database and object-storage data.

Backend, from `apps/backend`:

```bash
npm ci
npm run start:dev
npm run db:check
npm run build
npm run lint
npm test -- --runInBand
npm run test:e2e -- --runInBand
```

Mobile, from `apps/mobile`:

```bash
flutter pub get
flutter run
flutter analyze
flutter test # when tests exist or are added by the change
dart format --output=none --set-exit-if-changed lib
```

Use the narrowest relevant validation while iterating. Before handing off a
change, run the checks relevant to every app touched. Note that the backend
`lint` script includes `--fix` and can modify files; inspect its diff afterward.

## Change guidelines

- Keep backend features inside their existing NestJS feature modules and
  follow the controller/service separation already used in `src/`. Database
  tables are defined centrally in `src/database/schema.ts` and changed through
  versioned migrations under `apps/backend/drizzle`.
- Keep Flutter application changes under `apps/mobile/lib` unless the task is
  explicitly platform-specific. Treat Flutter-generated platform scaffolding
  as generated code.
- Preserve the existing API authentication and token-refresh flow when changing
  backend endpoints or the mobile API client; update both sides when a contract
  changes.
- Never commit `.env` files, credentials, build output, coverage, dependencies,
  or generated caches.
- Do not rewrite unrelated user changes. Check `git status` and review the final
  diff before handoff.
- Add or update focused tests when behavior changes. Do not claim checks passed
  unless they were actually run.

## Environment

The backend reads local configuration from `apps/backend/.env`. Use the example
values documented in the root `README.md`, but do not copy secrets into source,
logs, tests, or responses. Local infrastructure defaults are PostgreSQL on
`5432`, Redis on `6379`, and MinIO on `9000`/`9001`; the backend defaults to
`http://localhost:3000`.
