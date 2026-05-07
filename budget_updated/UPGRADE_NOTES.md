# Flutter Project Upgrade Notes

## Changes Made (Logic & Features UNCHANGED)

### pubspec.yaml
| Package | Old Version | New Version |
|---------|-------------|-------------|
| sdk environment | `>= 3.0.0` | `>= 3.3.0` |
| intl | ^0.18.1 | ^0.19.0 |
| drift | ^2.14.0 | ^2.18.0 |
| sqlite3_flutter_libs | ^0.5.0 | ^0.5.24 |
| path_provider | ^2.1.3 | ^2.1.4 |
| math_expressions | ^2.5.0 | ^2.6.0 |
| share_plus | ^10.0.0 | ^10.1.2 |
| googleapis | ^13.1.0 | ^13.2.0 |
| shared_preferences | ^2.2.3 | ^2.3.2 |
| carousel_slider | ^4.2.1 | ^5.0.0 |
| flutter_launcher_icons | ^0.10.0 | ^0.14.1 |
| package_info_plus | ^8.0.0 | ^8.1.0 |
| flutter_local_notifications | ^17.2.1+1 | ^17.2.3 |
| firebase_core | ^3.2.0 | ^3.6.0 |
| firebase_auth | ^5.1.2 | ^5.3.1 |
| cloud_firestore | ^5.1.0 | ^5.4.3 |
| local_auth | ^2.2.0 | ^2.3.0 |
| device_info_plus | ^10.1.0 | ^10.1.2 |
| flutter_timezone | ^1.0.8 | ^3.0.0 |
| device_preview | ^1.1.0 | ^1.2.0 |
| home_widget | ^0.5.0 | ^0.7.0 |
| material_symbols_icons | ^4.2768.0 | ^4.2795.0 |
| app_links | ^6.1.4 | ^6.3.2 |
| drift_dev (dev) | ^2.14.0 | ^2.18.0 |
| build_runner (dev) | ^2.4.7 | ^2.4.12 |

### android/build.gradle
- Kotlin version: `1.9.0` → `1.9.23`
- Android Gradle Plugin: `7.3.1` → `8.3.2`
- Google Services plugin: `4.3.14` → `4.4.2`
- Removed deprecated `jcenter()` repository

### android/app/build.gradle
- Java compatibility: `VERSION_1_8` → `VERSION_17` (required by AGP 8.x)
- Added `kotlinOptions { jvmTarget = '17' }`
- desugar_jdk_libs: `1.2.2` → `2.0.4`
- Firebase BOM: `31.1.1` → `33.5.1`
- kotlin-stdlib-jdk7 → `kotlin-stdlib-jdk8`
- androidx.window: `1.0.0` → `1.3.0`
- Added `ndkVersion "25.1.8937393"`

### android/gradle/wrapper/gradle-wrapper.properties
- Gradle: `7.5` → `8.6`

## Next Steps After Downloading
1. Run `flutter pub get` to regenerate pubspec.lock
2. Run `flutter pub upgrade` if you want to pull latest compatible versions
3. Run `flutter build apk` or `flutter run` to verify everything works
