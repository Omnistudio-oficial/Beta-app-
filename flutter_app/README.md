# Flutter migration base for OmniStudio

This folder contains the initial Flutter app scaffold configured with:

## Next steps
1. Copy the shared business logic from the existing Kotlin app.
2. Port UI screens one by one to Flutter widgets.
3. Reconnect Firebase services, auth, Firestore, messaging, and push notification settings.
4. Verify Android and iOS builds separately.

## App run
```bash
cd flutter_app
flutter pub get
flutter run
```


## Sara GitHub and Slack approvals

The Sara chat client understands the Staging Worker approval response. For a Staging build, point the client at the isolated Worker without changing the production default:

```bash
flutter run --dart-define=AI_AGENT_ULTIMATE_URL=https://ai-agent-ultimate-sara-staging.gonzalez24029.workers.dev/v1/chat
```

A supported GitHub repository creation or Slack message request returns a pending action. Sara displays the exact details and requires the user to tap **Confirmar y ejecutar** before the app calls `POST /v1/chat/actions/execute`. **Cancelar** discards the pending action locally. The backend enforces the one-time approval, five-minute expiry, authenticated Firebase UID and idempotency key.

The production Worker URL remains the default when `AI_AGENT_ULTIMATE_URL` is not supplied. Do not use the Staging build flag for a production release.
