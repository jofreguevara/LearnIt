# Repository Guidelines

## Project Structure
The repository contains the Flutter vertical slice and native integration seams. `lib/` holds UI, domain objects, and services; `native/` holds the shared C++ ABI; `android/` and `ios/` hold lock-screen audio integrations; `assets/topics/` contains bundled illustrations; and `test/` contains unit tests. Keep technical decisions and phase status in `docs/PLAN_TECNICO.md`.

## Build, Test, and Development
From the repository root, use:

```bash
flutter pub get
flutter analyze
flutter test
flutter test integration_test
flutter run
```

If the Flutter host files have not been generated, run `flutter create --platforms=android,ios .` first. Run native model and lock-screen tests on physical Android and iOS devices; emulators are not sufficient for performance or audio-background acceptance. The verified Linux environment installs Flutter under `/home/dev/tools/flutter` and the Android SDK under `/home/dev/android-sdk`; iOS builds still require macOS and Xcode.

## Coding Style
Use Dart/Flutter formatting with `dart format`, two-space indentation, `PascalCase` for types/widgets, `camelCase` for members, and `snake_case` for file names. Keep platform code idiomatic Kotlin/Swift and expose small, documented interfaces to the shared C++ core. Avoid blocking the UI thread; long inference and audio work belongs in native workers.

## Testing Guidelines
Add unit tests for state transitions, model-package verification, memory updates, and parsing. Add widget tests for session states and editable memories. Device tests must cover airplane mode, interruptions, screen lock, process termination, and recovery. Validate the exact model artifacts distributed; report latency, RAM, thermal behavior, battery, and bilingual quality by profile and device.

## Commits and Pull Requests
Use concise imperative commits with prefixes such as `feat:`, `fix:`, `docs:`, `test:`, or `build:` (for example, `docs: define offline model pipeline`). Pull requests should explain behavior and scope, link an issue when available, list validation commands and physical devices, and include screenshots or recordings for UI/audio changes. Call out model versions, hashes, licenses, and any changed privacy behavior.

## Agent Instructions
Resolve the project root before structural exploration. Check `.codegraph/` before broad searches; initialize it once only after this folder is a real project. Prefer `codegraph_explore` or read-only upstream CodeGraph commands, then explain any filesystem-search fallback. Keep each worktree under the user home with its own index. Rely on watcher sync; reserve `codegraph index` for explicit corruption recovery. Never use CodeGraph `uninit`, `install`, `uninstall`, or `upgrade`.
