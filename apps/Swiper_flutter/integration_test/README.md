# Swiper integration tests

## What’s here

- **`app_test.dart`** – Integration test that:
  1. Starts the app (Hive + ProviderScope + SwiperApp).
  2. On **web**, installs console capture (`window.onerror` and `unhandledrejection`).
  3. Taps “Skip to swipe” to go to the deck (starts session + deck load).
  4. Quickly taps “Likes” in the bottom nav (navigate away before load completes).
  5. Waits 2 seconds.
  6. Asserts that no captured console message contains “dispose” or “tried to use” (e.g. DeckNotifier-after-dispose).

- **`console_capture_stub.dart`** – No-op on non-web (no capture).
- **`console_capture_web.dart`** – Web-only: captures errors so the test can assert on them.

## How to run

From `apps/Swiper_flutter`:

**Recommended (automated):** The script starts ChromeDriver if needed and runs in release mode (reliable in CI/automation):

```bash
./scripts/run_integration_test_web.sh
# Headless: ./scripts/run_integration_test_web.sh --headless
```

**Manual:** Start ChromeDriver on port 4444, then:

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d chrome --release
```

Use `--release` so the drive avoids the debug connection (prevents AppConnectionException). See the project runbook (`docs/RUNBOOK_LOCAL_DEV.md`) for ChromeDriver install.
