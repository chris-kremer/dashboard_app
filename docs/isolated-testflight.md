# Isolated external TestFlight testing

Build 3.1 (10) starts fresh installs with a private on-device dataset and three
fictional example tasks. No login or API token is required. Existing configured
installs retain their connected backend; the mode is persisted in the App Group
so Lock Screen actions use the same dataset.

Test tasks, meals, caffeine, and manual sleep logs persist locally across launches.
All test-mode API calls are intercepted before URLSession. Cloud-only operations
fail locally; there is no fallback to production. Test caches and pending writes
have a separate namespace. Health import, browser activity, and cloud nudges are
unavailable in this mode. Data is not synced between devices.

## Review / tester instructions

1. Launch the app. The banner says “Test data · saved only on this device”.
2. Start an example task; pause, resume, and complete it. Try the Lock Screen controls.
3. Add tasks, meals, and caffeine. Try autocomplete after repeating an entry.
4. Inspect Timeline and Insights, then restart the app to check persistence.
5. Notifications are optional. Health permission and an account are not required.

This is not a multi-user cloud rollout. Do not supply the owner's production
API token or invite external testers through App Store Connect administrator roles.

## Regression checks

Run `bash tests/run-local-test-store-tests.sh` on macOS with Xcode installed.
It exercises the production local transport/store with a rejecting URLProtocol,
including persistence, task lifecycle, date filtering, autocomplete, concurrent
writes, account-mode migration, and zero network access in test mode.
