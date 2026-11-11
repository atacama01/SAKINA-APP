# SAKINA — Silent Timer

SAKINA is a simple Android application that helps you avoid forgetting your
phone in silent mode. Set a silent timer, and the app restores the previous
sound mode automatically when it ends. It can also silence your phone
automatically for each prayer after iqamah.

## Features

- 🔇 One-tap silent mode timer with quick presets and a custom duration.
- 🔔 Automatic sound restoration, plus a brief “Sound restored” notification.
- 📱 Quick Settings tile for instant silent mode.
- 🕌 Optional automatic prayer silence:
  - Fajr defaults to a 20 minute iqamah delay.
  - Dhuhr, Asr and Isha default to 15 minutes.
  - Maghrib defaults to 7 minutes.
  - Every prayer is silent for 20 minutes by default.
  - Every prayer, delay and duration can be changed independently.
- 🌍 Prayer times from the free [AlAdhan API](https://aladhan.com/prayer-times-api),
  using a manual city/country or the current GPS location.
- 💾 Prayer times are cached on the device. Native Android alarms keep working
  when the app is closed and are restored after a reboot.
- 🌙 Optional dark mode. The app follows the system theme by default and can be
  switched between system, light and dark from the icon in the top bar.
- 🚫 No account, API key, subscription or ads.

## Use Cases

**Mosque & Prayer**
Let SAKINA silence your phone at iqamah and restore the sound automatically
afterward.

**Exams**
Silence your phone for the duration of an exam without worrying about
forgetting to turn sound back on.

**Meetings**
Avoid interruptions while ensuring your phone returns to normal afterward.

**Study Sessions**
Stay focused without missing important calls later.

**Sleep**
Set silent mode before sleeping and automatically restore sound in the morning.

## Installation

Download the latest APK from the [Releases page](../../releases/latest), or
visit <https://github.com/atacama01/SAKINA-APP/releases>.

## Technology Stack

- Flutter
- Riverpod
- Flutter Local Notifications
- Android AlarmManager and broadcast receivers
- Shared Preferences

## Requirements

- Android 5.0 (API 21) or newer.

## Permissions

- **Notifications** — shows the active timer and prayer status messages.
- **Do Not Disturb access** — required to change the ringer mode.
- **Location** — only requested when you choose “Use my current location”.
- **Exact alarms** — recommended so prayer silence starts on time; Android 12+
  may ask you to allow it in Settings.

## Privacy

SAKINA does not collect personal information and does not require an account.
The app works on-device. When you refresh prayer times, only the city/country
or coordinates you choose are sent to the AlAdhan API to fetch the schedule.

## Building

```bash
flutter pub get
flutter run
```

The prayer auto-silence feature is Android-only. It uses native `AlarmManager`
alarms and broadcast receivers, so it does not depend on the Flutter process
staying alive.

## Contributing

Contributions, suggestions, and bug reports are welcome. Feel free to open an
issue or submit a pull request.
