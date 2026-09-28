# Tracker visual redesign

Approved direction: adaptive warm/sage surfaces, compact task rows, a full-day
timeline, and focused Insights with free-time details behind a disclosure.

## Preserved behavior

- Task search, ranking, priority/adjusted priority, estimates, notes and editing.
- Start/pause/resume, completion, snooze and delete (the latter actions are in the
  row menu; swipe actions remain available in Tasks).
- Multiple current tasks, quick task/activity, meal, coffee and sleep entry.
- Coverage-gap forms and notification deep links, including exact editable times.
- Food, caffeine, sleep and urgent-task statistics via Insights drill-downs.
- Raw sleep phases and raw browser sessions remain unchanged.
- Existing connected accounts stay connected; external testers remain isolated.

## Calculation and presentation rules

- Productive time is the union of actual productive intervals, never estimates.
- Paused intervals contribute logged time, but are not completed tasks.
- Missing historical fetches render as unavailable, not invented zeroes.
- Coverage retains the existing midnight-to-now definition and labels it clearly.
- The Today allocation prioritizes productive time when it overlaps free time;
  this prevents the displayed segments exceeding the actual day length.
- Free-time total is interval-unioned. Source totals may overlap.
- The timeline always spans 00:00–24:00; parallel intervals get separate tracks.
  Titles, exact times, priority and estimate are available in the selected-entry
  detail. Food/caffeine are point events, not invented one-minute activities.
- Nudge outcomes live in Settings and do not imply proof of causation.

## Verification

Run `bash tests/run-local-test-store-tests.sh` for storage/transport isolation,
task lifecycle, productive interval union, lane allocation and time formatting.
Build both the iPhone target and widget using the TrackerDashboard scheme.
On a fresh test-mode simulator check all five tabs, start/pause/resume/finish,
task editing and search, timeline selection, Insights drill-downs, and dark mode.
Test large text with long task titles; rows must wrap instead of clipping.

## Historical Timeline (build 12)

- Previous/next-day buttons, a bounded date picker, and a Today shortcut.
- Past snapshots are loaded directly without updating the shared current-day
  controller, widget cache, reminders, or workout importer.
- Past Health sleep is queried for the selected date; test mode never queries
  Health or production services. Browser sessions remain date-filtered.
- Historical entries are view-only. Errors offer Retry; a failed request never
  substitutes today's records. Cancelled/stale date loads cannot replace a newer
  selection, and entry selection resets when the displayed date changes.
- Regression tests cover historical task, meal, caffeine and sleep records and
  verify that fetching them leaves today's records unchanged.

## Layout polish (build 13)

- Status and category share a compact stack; the edit button retains its 44-point
  touch target without adding whitespace between the two labels.
- Custom tabs and the test-only banner reserve actual vertical layout space.
  Each tab explicitly hides the native iOS tab bar to avoid duplicate navigation.
- Priority tasks uses adaptive sage cards, a completion summary, open-first
  sections, compact metadata, and wrapping long names.
- Verified in an isolated iPhone 16e simulator: full Add capsule visible above
  the single custom tab bar, all four Add menu options, compact running-task
  header, and open/completed priority rows including a long task title.
- Storage/transport regression suite passed; no production records were changed.
