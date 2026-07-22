# Walkthrough - Replace Deprecated URL Constructor

I have updated the `app/build.gradle.kts` file to use the non-deprecated way of creating a `URL` object.

## Changes

### Build Configuration

#### [app/build.gradle.kts](file:///C:/Users/gagan/Projects/retro-mesh-console/android/app/build.gradle.kts)

- Swapped `import java.net.URL` for `import java.net.URI`.
- Updated the `downloadCores` task to use `URI(urlString).toURL()` instead of the deprecated `URL(urlString)` constructor.

```diff
-import java.net.URL
+import java.net.URI
...
-                val zipUrl = URL("${baseUrl}/${soName}.zip")
+                val zipUrl = URI("${baseUrl}/${soName}.zip").toURL()
```

## Verification Results

### Automated Tests
- Executed `./gradlew help` which successfully evaluated the build script, confirming the changes are syntactically correct and the `downloadCores` task is properly configured.
