# SAKINA — Silent Timer

SAKINA silences your phone for a chosen duration, and can optionally silence it
automatically for each prayer after iqamah.

## Features

- Quick presets, a custom timer, and a Quick Settings tile.
- Optional automatic prayer silence with per-prayer controls:
  - Fajr defaults to a 20 minute iqamah delay.
  - Dhuhr, Asr and Isha default to 15 minutes.
  - Maghrib defaults to 7 minutes.
  - Every prayer is silent for 20 minutes by default.
  - Each prayer can be enabled or disabled independently, and every delay and
    duration can be edited.
- Prayer times from the free [AlAdhan API](https://aladhan.com/prayer-times-api).
  No account, API key, subscription or ads are required.
- Manual city/country or current GPS location.
- Prayer times are cached on the device. The native Android alarm schedule keeps
  working when the app is closed and restores automatically after a reboot.
- A short “Sound restored” notification when a timer ends, and the timer
  notification is removed immediately when you stop it.

## Permissions

- **Do Not Disturb access** — required to change the ringer mode.
- **Notifications** — used for the active timer and prayer status messages.
- **Location** — only requested when you choose “Use my current location”.
- **Exact alarms** — recommended so prayer silence starts on time; Android 12+
  may ask you to allow it in Settings.

## Building

```bash
flutter pub get
flutter run
```

The prayer auto-silence feature is Android-only. It uses native `AlarmManager`
alarms and broadcast receivers, so it does not depend on the Flutter process
staying alive.
