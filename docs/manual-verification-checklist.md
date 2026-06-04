# Tracker Dashboard Manual Verification Checklist

## Sheet Migration

1. Keep `schedule` columns `A:K` unchanged.
2. Add `L Status`, `M CompletedAt`, and `N CompletedSource`.
3. Share the spreadsheet with `tracker-dashboard-worker@dashboard-app-498414.iam.gserviceaccount.com` as Editor.

Open tasks are rows with a task name, no `stop`, and `Status` not equal to `done` or `cancelled`.

## Cloudflare Worker

1. Deploy from `backend/worker`.
2. Set `APP_API_TOKEN` and `GOOGLE_SERVICE_ACCOUNT_JSON` with `wrangler secret put`.
3. Live deployment verified at `https://tracker-dashboard-worker.chriskremer-tracker.workers.dev`.
4. Live `/health`, `/snapshot`, and manual `/tasks/:rowNumber/complete` write were verified on June 4, 2026.

## iOS App

1. Run `TrackerDashboard`, not `TrackerDashboardWidgets`.
2. Enter the private API token in Settings.
3. Force refresh.
4. Confirm `Cached open tasks` is nonzero before testing widgets.
5. Add widgets manually from the simulator or device Home Screen.
