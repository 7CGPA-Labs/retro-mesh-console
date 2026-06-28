# Retro Mesh Console 🎮✨

A high-performance, self-contained cross-platform mobile application built with **Flutter (Dart)** that transforms your mobile devices into a localized video game emulation console and wireless gamepad controller mesh network.

It projects an independent gameplay viewport to a television (via native Android Cast SDK / iOS AirPlay UIWindow structures) while transforming the handheld smartphone screen into an ultra-low-latency wireless touch controller.

---

## ⚡ Key Capabilities

* **Symmetrical Dual-Role Entry Gate**: A single unified binary package that branches execution on boot based on user selection: **Host Console System** or **Join Controller Squad**.
* **Player 1 (Console Host Mode)**: Serves as the central computing unit. P1 selects a local ROM, boots an embedded `HttpServer` on port 3000, starts an active mDNS broadcast (`_retroconsole._tcp`), and maps virtual touch inputs directly to Port 1 of the FFI Libretro core.
* **Player 2 (Peripheral Client Mode)**: Automatically scans the local network via mDNS service discovery, establishes a persistent `WebSocketChannel` directly to P1, and acts as a touch gamepad mapped to Port 2 of the host's emulator core.
* **Low-Latency 2-Byte Input Protocol**: Bypasses text-based JSON encoding and serialization overhead to transmit real-time button transitions:
  * **Byte 0**: Action Phase (1 = KeyDown/Press, 2 = KeyUp/Release)
  * **Byte 1**: Button Identity (1=Up, 2=Down, 3=Left, 4=Right, 5=A, 6=B, 7=X, 8=Y, 9=START, 10=SELECT, 11=MENU, 12=PAUSE)
* **Dart FFI Libretro Core Wrapper**: Direct C/C++ FFI bindings to load compiled emulator binaries (`.so` / `.dylib`), managing native callbacks for video refresh frames, audio batch samples, and input polling.
* **Interactive Mock Fallback**: Includes a 60 FPS simulated graphics engine rendering bouncing interactive components and virtual button indicator chips to verify dual-device setups without requiring physical C/C++ core binaries.
* **Dual-Screen TV Projection**: Uses method channels to allocate native presentation boundaries:
  * **Android**: Renders on external displays using `android.app.Presentation` dialog views.
  * **iOS**: Listens for AirPlay connections to display root controllers in a secondary `UIWindow`.
* **Telemetry HUD**: Displays connection states (glowing green/red status chips), battery charge levels, and network connectivity indicators for both devices in a static bottom 80px HUD bar.

---

## 📁 Project Architecture

* **[`lib/main.dart`](file:///c:/Users/gagan/Projects/retro-mesh-console/lib/main.dart)**: Bootstraps the material MaterialApp, configures a retro dark theme, and loads the role selection gate.
* **[`lib/emulation/libretro.dart`](file:///c:/Users/gagan/Projects/retro-mesh-console/lib/emulation/libretro.dart)**: Implements Dart FFI bindings for Libretro cores, manages input buffers for Port 1/2, handles the 60 FPS game loop, and hosts the graphics fallback loop.
* **[`lib/network/host_server.dart`](file:///c:/Users/gagan/Projects/retro-mesh-console/lib/network/host_server.dart)**: Spins up the local server, manages Player 2 client sockets, and merges telemetry metrics.
* **[`lib/network/client_socket.dart`](file:///c:/Users/gagan/Projects/retro-mesh-console/lib/network/client_socket.dart)**: Discovers the console over mDNS, runs input event deduplication caching, and maintains the 8-second telemetry status interval.
* **[`lib/views/role_gate.dart`](file:///c:/Users/gagan/Projects/retro-mesh-console/lib/views/role_gate.dart)**: Welcome gate layout featuring visual selector cards and storage picker hooks.
* **[`lib/views/gamepad_deck.dart`](file:///c:/Users/gagan/Projects/retro-mesh-console/lib/views/gamepad_deck.dart)**: Symmetrical touch controller deck featuring zero-delay multi-touch `Listener` widgets, platform-channel presentation hooks, and a live preview of the TV Canvas and Telemetry HUD.
* **[`test/emulation_test.dart`](file:///c:/Users/gagan/Projects/retro-mesh-console/test/emulation_test.dart)**: Unit test suite asserting FFI structure mappings, input state caches, and telemetry serialization.

---

## 🛠️ Getting Started & Run Guide

### 1. Prerequisite: Place Emulator Core Binaries
Place your compiled Libretro core shared libraries in the `assets/cores/` directory:
* **Android**: `assets/cores/nestopia_libretro.so` (NES), `assets/cores/snes9x_libretro.so` (SNES), `assets/cores/genesis_plus_gx_libretro.so` (Sega Genesis)
* **iOS**: Cores must be compiled statically and linked in the Xcode project workspace.

### 2. Run the Automated Tests
Verify that the FFI structures, button mappings, and serialization formats are fully functional:
```bash
flutter test test/emulation_test.dart
```

### 3. Build & Run the App
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
