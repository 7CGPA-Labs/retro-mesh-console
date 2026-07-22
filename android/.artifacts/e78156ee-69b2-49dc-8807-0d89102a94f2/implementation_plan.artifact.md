# Fix Sync and Build Errors

The project is currently experiencing two main issues:
1. **Sync Error**: A `NoSuchMethodError` during C++ configuration, caused by a mismatch between Android Gradle Plugin (AGP) 8.3.2 and Gradle 9.6.1.
2. **Build Error**: AAPT2 failure when compiling `app_icon.png` in the `release` build.

## Proposed Changes

### Build Configuration

#### [MODIFY] [root build.gradle.kts](file:///C:/Users/gagan/Projects/retro-mesh-console/android/build.gradle.kts)
- Upgrade AGP to `9.3.0`.
- Upgrade Kotlin to `2.4.10`.

#### [MODIFY] [settings.gradle.kts](file:///C:/Users/gagan/Projects/retro-mesh-console/android/settings.gradle.kts)
- Upgrade AGP to `9.3.0`.
- Upgrade Kotlin to `2.4.10`.

#### [MODIFY] [app/build.gradle.kts](file:///C:/Users/gagan/Projects/retro-mesh-console/android/app/build.gradle.kts)
- Update Compose configuration for Kotlin 2.x compatibility.
- Enable the new Kotlin Compose compiler plugin.

### Resources

#### [INVESTIGATE] [app_icon.png](file:///C:/Users/gagan/Projects/retro-mesh-console/android/app/src/main/res/drawable-nodpi/app_icon.png)
- Check if the file is a valid PNG. If not, I may need to suggest a replacement or a way to fix it.

## Verification Plan

### Automated Tests
- Run `gradle sync` to verify the C++ configuration issue is resolved.
- Run `./gradlew assembleDebug` to verify the main build.
- Run `./gradlew :app:mergeReleaseResources` specifically to test the AAPT2 issue.

### Manual Verification
- Verify that the IDE syncs without errors.
