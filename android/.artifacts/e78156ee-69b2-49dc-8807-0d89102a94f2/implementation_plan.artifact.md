# Replace Deprecated URL Constructor

The `java.net.URL(String)` constructor is deprecated since Java 20. The recommended approach is to use `java.net.URI` to parse the string and then convert it to a `URL`.

## Proposed Changes

### Build Configuration

#### [MODIFY] [app/build.gradle.kts](file:///C:/Users/gagan/Projects/retro-mesh-console/android/app/build.gradle.kts)

- Import `java.net.URI`.
- Replace `URL(urlString)` with `URI(urlString).toURL()`.

## Verification Plan

### Automated Tests
- Run `./gradlew downloadCores` to ensure the core downloading logic still works correctly.
- Run `./gradlew help` to ensure the build script compiles without warnings/errors related to `URL`.

### Manual Verification
- None required beyond ensuring the build script runs.
