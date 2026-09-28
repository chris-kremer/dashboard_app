# Merc handoff: project-aware daily rollover

Tracker now distinguishes logical tasks from individual daily rows/work intervals.

## Required Sheet contract

- `schedule!U1` is `task_id`. Column U holds an opaque stable task ID (UUID).
- **Preserve U unchanged when copying an unfinished task to another date, rescheduling it, renaming it, or creating a resumed work interval.** Preserve the original rows and their IDs as history.
- A genuinely new task gets a new UUID, even if its title matches an older task. Never reuse a completed task's ID for a new occurrence of a recurring task.
- If a legacy task has no ID, assign one to the source row BEFORE making its next copy, and copy that same ID into U on the new row. Do not bulk-match old rows by title.
- Never put a date, row number, project name, or group name in U. Never overwrite a nonempty ID to “refresh” it.
- Keep existing A:T meanings. Copy formulas with the correct destination references. New daily rows must not duplicate yesterday's actual work: clear actual start/stop and completion timestamps as your rollover normally does. The stable task ID is metadata, not an event.
- Do not delete/reorder rows concurrently with app writes. Prefer editing a task's date in its existing row for rescheduling. App row IDs such as `schedule:123` remain row addresses, NOT task identities.
- Avoid creating a second current-day copy when that task ID already has an appropriate current-day row. Current and future copies of one task keep the same ID. Independent planned occurrences require separate IDs.

## Project behavior

- Projects, nested groups, checklist steps, membership and explicit missing-task resolutions are stored in the authenticated Cloudflare ProjectCoordinator, not in category names or comments. Do not alter that metadata just to roll the date forward.
- Projects use today's tasks and future tasks, deduplicated by U. Historical rows are not resurrected automatically and do not inflate task counts.
- A project task that was last open in the past with no current/future copy prompts Chris: Keep (restore today), Mark done, or Discard. These decisions do not rewrite historical intervals.
- Keep date rollover on the Google/agent side. The app does not perform its own general rollover.
- Today's latest interval determines current status for a task ID. Older open/paused rows are not separate to-dos.

## Optional agent integration

Use the existing authenticated Worker URL/token; never paste tokens into chat or commit them.

- `GET /projects` returns `revision`, `projects`, `groups`, `memberships`, and `schedule`.
- `PUT /projects` updates metadata with the last observed `revision` (409 means refresh, do not overwrite). Retain unrelated records. Do not submit the schedule array as a mutation.
- `POST /projects/link`: `{revision, rows: [{rowNumber, task, date, taskId?}], projectId?, groupId?}` moves selected tasks, assigning missing IDs safely. Omit projectId/groupId to move to Other tasks while retaining checklist data. The row's name/date fingerprint must still match.
- `POST /projects/resolve`: `{revision, taskId, action: "keep" | "done" | "discarded"}` resolves a genuinely missing task. `keep` always restores today.
- `POST /tasks` accepts optional `taskId`; omit it for genuinely new tasks. Send the existing ID for another interval of the SAME task.

Column U must be unused or already labeled `task_id`; the Worker refuses to overwrite unrelated U data. Before the next rollover, acknowledge this contract and verify that a copied project task keeps its original U value.
