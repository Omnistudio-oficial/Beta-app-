# Flutter migration base for OmniStudio

This folder contains the initial Flutter app scaffold configured with:
- Android package: `com.aistudio.omnistudio.wkspea`
- iOS bundle identifier: `com.aistudio.omnistudio.wkspea`

## Next steps
1. Copy the shared business logic from the existing Kotlin app.
2. Port UI screens one by one to Flutter widgets.
3. Reconnect Firebase services, auth, Firestore, messaging, and push notification settings.
4. Verify Android and iOS builds separately.

## Package IDs used
- Android: `com.aistudio.omnistudio.wkspea`
- iOS: `com.aistudio.omnistudio.wkspea`

## App run
```bash
cd flutter_app
flutter pub get
flutter run
```
