# Notti Memory Refactor Implementation Plan

> Spec: [Notti Memory Redesign](../specs/2026-08-06-notti-memory-redesign.md)

Scope: shared iOS domain/UI, with a free-only backend extractor transport. Work
directly on `main` per `AGENTS.md`. Do not commit or push unless requested.

## Status

Implementation is complete as of 2026-08-06 for both iOS targets and the
free-target backend source. Swift syntax parsing, backend syntax, all 23 Node
tests, project/localization plist lint, legal-claim scans, compatibility-name
scans, and `git diff --check` pass.

XCTest and Simulator builds were intentionally not run because this machine's
Simulator environment is unreliable; the user will validate with the physical
device workflow. Production deployment of `/ai/memory/extract` remains a
separately authorized operation and has not been performed. No commit or push was
created.

## Task 1: Compatibility Naming

1. Add decoding tests for `AppTab` and `RecordSource` accepting legacy `spark`.
2. Rename current Spark source/test symbols, paths, logger category, project group,
   and visible UI to Notti.
3. Keep explicit legacy raw strings and fixture names only where migration needs
   them.
4. Run Swift parse checks and `ProjectConfigurationTests`.

## Task 2: Domain And Encrypted Repository

1. Add failing tests for snapshot round-trip, serialized concurrent writes,
   key/decrypt failure preservation, corrupt-vector recovery, and complete delete.
2. Implement `NottiMemory`, evidence, revisions, links, pending items, jobs, and
   encrypted snapshot/vector envelopes.
3. Implement `actor NottiMemoryRepository` as the only write authority.
4. Run `NottiMemoryRepositoryTests`.

## Task 3: Migration

1. Add legacy memory/conversation/history/settings/folder fixtures.
2. Implement `NottiMigrationCoordinator` with content-hash idempotency and verified
   copy-before-select behavior.
3. Migrate sensitive legacy memory to pending and retain legacy sources.
4. Run `NottiMigrationCoordinatorTests` and persistence recovery tests.

## Task 4: Hybrid Retrieval And Lifecycle

1. Add tests for CJK tokenization, BM25, entity penalty, temporal hits, half-life,
   separate evidence/access boosts, Top-K, character budget, and embedding fallback.
2. Implement hybrid scoring and encrypted vector sidecar integration.
3. Implement expiry/archive maintenance and successful-injection touch semantics.
4. Run `NottiMemorySearchTests`.

## Task 5: Extraction And Resolver

1. Add strict JSON, invalid ID, deduplication, merge, supersede, pattern activation,
   sensitive confirmation, and forbidden-secret tests.
2. Implement the shared extraction protocol and direct BYOK extractor.
3. Implement the free-only `BackendNottiMemoryExtractor` and `/ai/memory/extract`.
4. Persist jobs before extraction and enforce three attempts/seven days.
5. Run iOS extraction tests and `npm test` in `notiee-ping-stream`.

## Task 6: Chat And Agent Integration

1. Add tests for recall-before-answer, touch-after-success, no touch on failure,
   and asynchronous extraction.
2. Inject an escaped JSON memory data block into the prompt.
3. Remove answer CRUD tags, personal-info trigger extraction, and ten-round
   compression.
4. Replace `memory_get` with bounded `memory_search`; hard delete remains a
   separately confirmed destructive action.
5. Run Notti ViewModel, prompt, and Agent tests.

## Task 7: Management UI And Product Migration

1. Add searchable active/pending/archived memory views with category filters,
   confirmation, edit, restore, export, single delete, and clear-all confirmation.
2. Add automatic-write and memory-use settings with a new versioned privacy gate.
3. Migrate generated folders using `systemRole`, preserving UUIDs.
4. Update all three localizations, bundled legal HTML, website mirror, and current
   product docs while preserving historical changelogs/specs.

## Task 8: Verification

1. [x] Run `rg` for non-compatibility Spark references in current source/UI.
2. [ ] Run focused and full Notti XCTest through the user's physical-device
   workflow; Simulator XCTest is intentionally skipped on this machine.
3. [ ] Validate both `Notiee` and `Notiee+` on physical devices; Simulator builds
   are intentionally skipped on this machine.
4. [x] Run backend syntax check and full Node tests.
5. [x] Update `HANDOFF.md` in English with results and remaining deployment/device
   QA.
