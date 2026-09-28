# Projects and nested groups

## Behavior

- Tasks opens in Projects by default, with a remembered flat-list toggle. Standalone tasks compete in the same priority ordering using the existing adjusted-priority rules.
- Top-level projects have optional default categories and deadlines. Nested groups support arbitrary depth, parent navigation and ancestor menus; cycle creation/moves are prohibited.
- Tasks can be added inside a project/group, moved in batches, or reassigned in their editor. Categories stay independently editable. Task editors support lightweight checklists, including standalone tasks.
- Timers stay on tasks. Resume in both app and Live Activity preserves the stable ID. Project/group time uses the union of actual work intervals per day, not estimates or duplicated overlapping time.
- Column U holds `task_id`; row IDs remain interval addresses. Current-day rows win over historical copies; future copies are Upcoming, deduplicated by stable ID. Names never establish identity.
- Missing historical project tasks require explicit Keep/Done/Discard. Keep writes a new current-day row with the same ID. Done/Discard changes project metadata only, not Sheet history.
- A transition to all tasks done asks whether to close the project. Future/missing unresolved work prevents the suggestion. Closure preserves metadata/history and can be reversed.
- The bottom tab bar reserves real layout space and uses expanding rounded selection backgrounds around both icon and label.

## Storage and safety

- Authenticated `ProjectCoordinator` Durable Object stores versioned metadata with optimistic concurrency (409 for stale revisions), separate from nudge state.
- App task writes are serialized through this coordinator so app creates/restores do not race each other for the next Sheet row. External direct Sheet writers still need to coordinate row writes.
- Row assignment verifies row number/name/date/previous identity before stamping U. U is never overwritten if its header or existing content belongs to something else.
- External test mode routes every project operation to its isolated local database. No fallback to the production service.
- No bulk migration by title, historical cleanup, sheet deletion, production-data fixture or credential changes.
- Merc must honor `docs/merc-project-task-identity.md` before the next rollover.

## Verification

- Worker: 46 tests passing, including nested-group cycles, cross-project moves, stable IDs, stale revision rejection, row fingerprint validation, idempotent missing-task retries, and preserving historical status. TypeScript passes.
- Swift local transport/storage/model tests pass, including today's/future/historical deduplication, missing-task restore, closure, standalone checklists and network isolation.
- iOS Simulator Debug build succeeds for arm64 and x86_64.
- Disposable iPhone 16e / iOS 18.3: visually checked project overview, two nested group levels, Today breadcrumbs, and complete bottom navigation in light/dark and larger text sizes. Fictional fixtures only.
- Project create form renders correctly; simulator accessibility omits some native navigation controls, so form persistence is covered by API/storage tests rather than claiming a completed UI save test.

## Release gate

Deploy and verify the Worker before pushing the app release to main / TestFlight. Cloudflare authorization expired during this implementation; no production deployment has been claimed. Check U's identity-column contract and authenticated `/projects` after authorization, then release the app.
