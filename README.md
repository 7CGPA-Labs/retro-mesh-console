# Mojo Snap 🎮✨
*Built by 7CGPA Labs*

[![Android Build](https://github.com/7CGPA-Labs/retro-mesh-console/actions/workflows/android.yml/badge.svg)](https://github.com/7CGPA-Labs/retro-mesh-console/actions/workflows/android.yml)
[![iOS Build](https://github.com/7CGPA-Labs/retro-mesh-console/actions/workflows/ios.yml/badge.svg)](https://github.com/7CGPA-Labs/retro-mesh-console/actions/workflows/ios.yml)

🌐 **[Visit the Official Mojo Snap Console Website](https://7cgpa-labs.github.io/retro-mesh-console/)**

A high-performance, cross-platform mobile application built with **Flutter (Dart)** that transforms your smartphone into both a localized video game emulation console and an ultra-low-latency wireless gamepad controller. 

It projects the gameplay directly to a wireless television (via Miracast Android Presentation API / iOS AirPlay) while transforming your mobile device's screen into an immersive, edge-to-edge touch controller.

---

## ⚡ Key Capabilities

* **Symmetrical Dual-Role Entry Gate**: A single binary that allows the user to boot as either the **Host Console System** (projects to TV) or join as a **Client Controller** (Player 2 gamepad).
* **True Full-Screen Immersive Gamepad**: The virtual gamepad automatically morphs to match the console you are playing (NES, SNES, Genesis, PS1). It runs in true immersive mode (no status bar or navigation gestures) with native multi-touch high-frequency polling.
* **Native C++ Audio & Video Pipelines**: Achieves consistent, low-latency audio-video synchronization by minimizing Dart FFI overhead. The Libretro core pushes audio and video frames directly into C++ threads (`miracast-render.cpp`, `miracast-audio.cpp`), where they are consumed effectively by Android's AAudio, EGL contexts, and iOS's CoreAudio layers.
* **Dart FFI Libretro Core Wrapper**: Direct C/C++ FFI bindings load compiled emulator binaries (`.so` / `.dylib`) and manage memory serialization for the instant Quick Save and Quick Load functionality. 
* **Low-Latency Native Input Protocol (Player 2)**: Player 2 inputs bypass Flutter entirely. Physical screen taps on the Client send tiny packets over a raw TCP socket. The Native OS layer (Kotlin/Swift) receives these packets and directly updates the thread-safe C++ input array for the emulator core via JNI/FFI, aiming for sub-millisecond network transmission.
* **Dual-Screen TV Projection**: 
  * **Android**: Renders on external displays using `android.app.Presentation` dialog views.
  * **iOS**: Listens for AirPlay connections to display root controllers in a secondary `UIWindow`.

---

## 📁 Project Architecture

* **`lib/main.dart`**: Bootstraps the app and loads the role selection gate.
* **`lib/emulation/libretro.dart`**: High-level Dart wrapper that utilizes `dart:ffi` to bridge the native Libretro C APIs, managing emulation lifecycle, paused states, and save-state memory serialization.
* **`lib/emulation/core_router.dart`**: Smart routing that maps file extensions to emulator cores automatically.
* **`lib/views/gamepad_deck.dart`**: The edge-to-edge virtual controller featuring dynamic layouts, multi-touch `Listener` widgets, and the in-game quick-action menu.
* **`android/app/src/main/cpp/miracast-audio.cpp` / `miracast-render.cpp`**: Pure native C++ drivers for low-latency AAudio and double-buffered EGL rendering to external `ANativeWindow` surfaces.
* **`android/app/src/main/kotlin/dev/seven_cgpalabs/mojosnap/NetworkManager.kt`**: Native Android implementation for raw TCP sockets, routing Player 2 controller inputs directly into the C++ bridge.
* **`ios/Runner/retro-bridge.mm`**: Fully synchronized iOS native layer that supports Analog joysticks, DS touch pointers, and precise pixel format rendering environments.

---

## 🛠️ Getting Started & Run Guide

### 1. Download Emulator Cores
You no longer need to manually manage core files! We have included a Dart script that automatically downloads the latest stable Libretro cores straight from the BuildBot servers and extracts them into your assets folder.

Run the following command from the root of your project:
* **For Android:**
  ```bash
  dart run scripts/download_cores.dart android
  ```
* **For iOS:**
  ```bash
  dart run scripts/download_cores.dart ios
  ```

### 2. Build & Run the App
Connect two mobile devices to the **same Wi-Fi network**.

* **For Android**:
  ```bash
  flutter run -d <device_1_id> # Player 1 (Console Host)
  flutter run -d <device_2_id> # Player 2 (Client Controller)
  ```
* **For iOS** (Requires macOS & Xcode):
  ```bash
  flutter run -d <device_id>
  ```

---

## ⚙️ Mobile OS Configuration Details

Local network broadcasting (mDNS) and dual-device communications are fully configured in the build manifests:

### Android Manifest (`android/app/src/main/AndroidManifest.xml`)
Added permissions for internet connectivity and multicast locks:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### iOS Info (`ios/Runner/Info.plist`)
Registered Bonjour service identifiers to pass iOS 14+ local network discovery sandboxing checks:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Retro Mesh Console uses the local network to discover and connect controllers for multiplayer gameplay.</string>
<key>NSBonjourServices</key>
<array>
    <string>_retroconsole._tcp</string>
</array>
```
