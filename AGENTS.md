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

## Cross-stack orchestration policy

For any feature that changes behavior or an API contract in both
`apps/mobile` and `apps/backend`, use a planning-first orchestration workflow:

1. Act as the orchestrator and inspect both applications before assigning work.
2. Produce one implementation plan that defines the API method and route,
   authentication, request, response and error shapes, field types and
   nullability, ownership of files, migrations, and validation for both sides.
3. Do not modify implementation files until the user approves the plan, unless
   the user has already explicitly approved an equally specific plan in the
   current task.
4. After approval, delegate the implementation to two subagents in parallel:
   one mobile worker and one backend worker.
5. Give each worker the agreed contract and keep its write scope disjoint. Use
   separate worktrees when the orchestration environment provides them;
   otherwise enforce the directory boundaries below in the shared workspace.
6. Wait for both workers to finish and require each to report changed files,
   assumptions, and validation results.
7. Review the two implementations together, resolve integration issues within
   the approved plan, and run the relevant checks for every touched app.
8. Present one combined final review to the user.

Features confined to one application do not require this two-worker workflow.
The orchestrator owns changes to shared root files, documentation, and
infrastructure unless their ownership is explicitly assigned in the approved
plan. Workers must read this file and any more specific `AGENTS.md` in their
scope before making changes. If a worker discovers that a change outside its
assigned scope is necessary, it must return that work to the orchestrator
instead of editing the other scope.

### Mobile worker

Write scope: `apps/mobile/**` only.

Responsibilities:

- Flutter and Dart implementation under `lib/` by default.
- UI, state management, API client, serialization, and models.
- Focused Flutter tests for changed behavior.
- Run `flutter analyze`, relevant `flutter test` targets, and Dart formatting
  checks from `apps/mobile` as appropriate.

Do not modify backend, root, infrastructure, or generated platform files unless
the approved plan explicitly expands the scope.

### Backend worker

Write scope: `apps/backend/**` only.

Responsibilities:

- NestJS implementation using the existing controller/service separation.
- API endpoints, DTOs, contracts, authentication behavior, and error handling.
- Drizzle schema changes and versioned migrations when required.
- Focused backend tests for changed behavior.
- Run the relevant database check, build, unit tests, and e2e tests from
  `apps/backend` as appropriate. Run `npm run lint` only with awareness that it
  modifies files, and inspect its diff afterward.

Do not modify mobile, root, or infrastructure files unless the approved plan
explicitly expands the scope.

### Integration review

After both workers finish, the orchestrator must verify:

- HTTP methods, routes, authentication, and token-refresh assumptions.
- Request and response field names, types, nullability, serialization, and
  status codes.
- Error response shapes and client-side handling.
- Database schema changes, migrations, and compatibility assumptions.
- Relevant unit, widget, integration, and e2e tests and builds.
- Both workers' diffs and the final `git status`, including any unexpected or
  overlapping edits.

Do not silently resolve architectural or contract disagreements between the
workers. Resolve them against the approved plan when possible; otherwise report
the disagreement and ask the user for a decision before expanding or changing
the agreed architecture.

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
