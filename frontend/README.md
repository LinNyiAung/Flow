# frontend

A new Flutter project.

## Backend URL

The API base URL defaults to production (`https://flowfinance.onrender.com`).
To run against a backend on your LAN (e.g. a dev machine running uvicorn on
port 8000), pass it at build/run time:

```sh
flutter run --dart-define=API_BASE_URL=http://10.80.21.130:8000
```

Cleartext HTTP to that LAN address is allowed on Android by
`android/app/src/main/res/xml/network_security_config.xml`; production stays
on HTTPS.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
