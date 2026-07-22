# Retro Mesh Console (Mojo Snap)

A high-performance, native Android retro gaming console built specifically for flawless Miracast TV streaming. Built entirely with **Kotlin Jetpack Compose** for a beautiful gamepad UI, and a pure **C++ Native JNI Engine** for zero-latency Libretro emulation.

## Highlights
* **Zero-Friction Build System**: Gradle automatically downloads and injects Libretro cores during compilation. No manual setup required!
* **Pure Native Kotlin + C++**: 100% Native Android application. Completely purged of legacy Flutter, Dart, and Google Cast bloatware.
* **Bulletproof Miracast Integration**: Instantly cast to any Miracast-enabled TV using Android's native `DisplayManager`.
* **Hardware-Bypassing Software Renderer**: Uses highly optimized `ANativeWindow_lock` direct-CPU memory copying for TV rendering. By bypassing the GPU and OpenGL, it completely eliminates driver crashes and black-screen issues on buggy TV virtual displays.
* **Intelligent Thermal Management**: Features an automatic CPU thermal throttling bridge between Android's `PowerManager` and the C++ engine. Seamlessly drops frame rates on the TV output to prevent device overheating without affecting audio or game speed.
* **Multi-touch Gamepad**: High-fidelity, mathematically precise virtual analog sticks and d-pads built entirely in Jetpack Compose with haptic feedback.

## How to Build
This project is a standard native Android Gradle project.

1. Clone the repository.
2. Open the `android/` directory in Android Studio.
3. Click "Run" (or use `./gradlew assembleDebug` from the command line).

*Note: The Gradle build will automatically fetch the latest `arm64-v8a` Libretro cores from the libretro buildbot and bundle them into your APK.*

## Architecture
* **UI & Gamepad**: `android/app/src/main/java/.../ui/GamepadDeckScreen.kt` (Jetpack Compose)
* **Emulation Core**: `android/app/src/main/cpp/libretro-frontend.cpp` (C++)
* **Display Engine**: `android/app/src/main/cpp/miracast-render.cpp` (C++)
* **Casting API**: `android/app/src/main/kotlin/.../CastingAdapter.kt` (Kotlin)
* **Thermal Manager**: `android/app/src/main/kotlin/.../ThermalManager.kt` (Kotlin)
