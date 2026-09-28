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

## Release verification — September 28, 2026

- Cloudflare authorization renewed. Worker version `60aa6f3a-dfcc-4eac-9784-a4538eb1bc2a` deployed at 13:10 UTC; deployment listing confirms 100% traffic.
- Public `/health` returns HTTP 200 with `ok: true`; unauthenticated `/projects` returns HTTP 401.
- The private live-data check remains unverified: Chris approved a read-only check using the app's Keychain token, but no readable token exists in this Mac's Keychain. No credential was displayed/saved and no production task/project fixtures were written. Column U's live contents have not been independently inspected; write-time collision safeguards remain enabled.
- Signed release archive `3.1 (14)` succeeded. TestFlight upload status is tracked in the task's release output, not inferred from archive success.
- Merc must preserve `task_id` in column U during rollover. The handoff instructions are part of this commit.
