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

## Browser Usage as Free Time

1. Configure and deploy the live heartbeat Worker described below.
2. Enter the add-on token in both Firefox extension popups.
3. Browse YouTube/X, wait 90 seconds for an inactive session to close, and force-refresh the app.
4. Confirm YouTube/X totals appear under **Insights → Tracked Free Time**.
5. Confirm separate YouTube/X sessions appear as purple blocks in Timeline rather than one all-day block.

## Live Watch Nudges

1. Create an Apple Push Notifications signing key (`.p8`) in the Apple Developer portal.
2. From `backend/worker`, configure secrets:
   - `npx wrangler secret put ADDON_API_TOKEN`
   - `npx wrangler secret put APNS_KEY_ID`
   - `npx wrangler secret put APNS_TEAM_ID`
   - `npx wrangler secret put APNS_PRIVATE_KEY`
   - `npx wrangler secret put APNS_TOPIC` (`com.chriskremer.TrackerDashboard`)
3. Deploy with `npx wrangler deploy`.
4. Install and open a development-signed build on the physical iPhone, allow notifications, and tap **Save nudge settings**.
5. Tap **Send test nudge**, lock the iPhone, and confirm the alert taps the unlocked, worn Apple Watch.
6. Paste the same `ADDON_API_TOKEN` into both Firefox extension popups and confirm **Save & test heartbeat** reports Connected.
7. Start a YouTube video or actively browse X and confirm the first nudge arrives after the configured delay.
8. Confirm the alert offers no stop, snooze, pause, or skip actions.
9. Keep browsing and confirm follow-up wording and timing vary, averaging roughly two minutes.
10. Close YouTube/X and confirm a positive notification arrives with the gentler reward sound.
11. Open the reward notification and confirm the green celebration animation and success haptic appear in the app.
