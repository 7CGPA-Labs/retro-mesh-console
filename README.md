# Retro Mesh Console (Mojo Snap)

A high-performance, native Android retro gaming console built specifically for flawless Miracast TV streaming. Built with **Kotlin Jetpack Compose** for a beautiful UI and a pure **C++ Native JNI Engine** for zero-latency Libretro emulation.

## Features
* **Zero-Friction Build System**: Gradle automatically downloads and injects Libretro cores during compilation!
* **Native C++ Emulation**: Libretro engine fully implemented in C++ to avoid JNI overhead per frame.
* **Miracast Integration**: Instantly cast to any Windows 11 PC or Miracast-enabled TV using Android's native `DisplayManager` and `Presentation` APIs.
* **Multi-touch Gamepad**: High-fidelity, mathematically precise virtual analog sticks and d-pads built entirely in Jetpack Compose.

## How to Build
This project has been completely migrated to a standard Android Gradle project. **Flutter is no longer required**.

1. Clone the repository.
2. Open the `android/` directory in Android Studio.
3. Click "Run" (or use `./gradlew assembleDebug` from the command line).

*Note: The Gradle build will automatically fetch the latest `arm64-v8a` Libretro cores from the buildbot and bundle them into your APK.*

## Architecture
* **UI**: `android/app/src/main/java/.../ui/` (Jetpack Compose)
* **Emulation Engine**: `android/app/src/main/cpp/libretro-frontend.cpp` (C++)
* **Casting API**: `android/app/src/main/java/.../CastingAdapter.kt` (Kotlin)
