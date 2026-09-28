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
