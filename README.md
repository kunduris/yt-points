# YT Points
Flutter Android family rewards wallet. Each point is worth $0.50.

## GitHub Actions setup
In repository Settings > Secrets and variables > Actions:
- Under **Variables**, add `SUPABASE_URL` with the API URL from your Supabase project.
- Under **Secrets**, add `SUPABASE_PUBLISHABLE_KEY` with the project's publishable API key (not service role).
Then open Actions > Build Android APK > Run workflow. Download the `yt-points-apk` artifact after success.

## Local build
Run `flutter create --platforms=android --org com.ytpoints .` once, then `flutter pub get`.
Run `flutter build apk --release --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY`.
The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

## Notes
This is a first version. A release build has not yet been verified. Parent sign-in uses Supabase Auth email/password. Children do not sign in. Purchases must be multiples of $0.50; the database currently has no transactional overdraft enforcement for concurrent devices.
