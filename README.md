# Retro Mesh Console (Mojo Snap)

A high-performance, native Android retro gaming console built specifically for low-latency Miracast TV streaming and wireless multiplayer mesh play. Built entirely with **Kotlin Jetpack Compose** for a modern touch gamepad interface, and a pure **C++ Native Libretro Engine** for fast emulation.

---

## 🌟 Highlights

* **Zero-Friction Build System**: Gradle automatically downloads and packages the required `arm64-v8a` Libretro cores from the official Libretro buildbot during compilation. No manual core installation required!
* **Pure Native Kotlin + C++**: 100% native Android application with zero hybrid/web bloatware.
* **Dynamic Resolution & Geometry Engine**: Real-time resolution and buffer geometry tracking (`ANativeWindow_setBuffersGeometry`) ensuring pixel-perfect scaling for all cores including PS1 (PCSX ReARMed), SNES, Genesis, and GBA.
* **RetroArch-Standard Controller Subsystem**: 100% standard Libretro RetroPad mapping (`RETRO_DEVICE_ID_JOYPAD_*`) with:
  * Dynamic virtual gamepad UI tailored per console (SNES, PS1, Genesis 6-button, NES/GB).
  * Seamless bidirectional analog-to-digital and digital-to-analog fallbacks.
  * Full bitmask query support (`RETRO_DEVICE_ID_JOYPAD_MASK`).
  * Out-of-the-box plug-and-play support for physical Bluetooth & USB gamepads (Xbox, PlayStation DualShock/DualSense, 8BitDo, Switch Pro).
* **Wireless Multiplayer Mesh**: Local network zero-configuration discovery (NSD/mDNS) with secure 6-digit PIN pairing for wireless 2-Player co-op and versus gaming.
* **Bulletproof Miracast Integration**: Instantly cast to any Miracast-enabled TV or wireless display adapter using Android's native `DisplayManager` and presentation mode formatted to 4:3 CRT aspect ratios.
* **Hardware-Bypassing Software Renderer**: Utilizes optimized direct-CPU memory streaming into `ANativeWindow_lock` buffers to eliminate GPU context switches and black-screen bugs on TV virtual displays.
* **Intelligent Thermal Management**: Active power and thermal throttling bridge between Android's `PowerManager` and native emulation engine, intelligently pacing video frames to keep CPU thermals cool during long sessions.

---

## 🎮 Supported Systems & Cores

| Console | Core | File Extensions |
| :--- | :--- | :--- |
| **Sony PlayStation (PS1)** | `pcsx_rearmed` | `.bin`, `.cue`, `.iso`, `.img` |
| **Super Nintendo (SNES)** | `snes9x` | `.smc`, `.sfc` |
| **Nintendo Entertainment System (NES)** | `fceumm` | `.nes` |
| **Game Boy Advance (GBA)** | `mgba` | `.gba` |
| **Game Boy / Game Boy Color** | `gambatte` | `.gb`, `.gbc` |
| **Sega Genesis / Mega Drive** | `genesis_plus_gx` | `.md`, `.sms`, `.gg` |
| **DOS PC** | `dosbox_pure` | `.exe`, `.bat`, `.com`, `.zip` |

---

## 🕹️ Controller Mapping Standards

Mojo Snap adheres strictly to the official **Libretro / RetroArch RetroPad** standard:

| RetroPad Standard ID | Action / Button | PS1 Mapping | SNES Mapping | Genesis Mapping | NES Mapping |
| :---: | :---: | :---: | :---: | :---: | :---: |
| `0` | **B** (Bottom) | ✕ (Cross) | B | B | B |
| `1` | **Y** (Left) | □ (Square) | Y | A | — |
| `2` | **SELECT** | Select | Select | Mode | Select |
| `3` | **START** | Start | Start | Start | Start |
| `4` | **UP** | D-Pad Up | D-Pad Up | D-Pad Up | D-Pad Up |
| `5` | **DOWN** | D-Pad Down | D-Pad Down | D-Pad Down | D-Pad Down |
| `6` | **LEFT** | D-Pad Left | D-Pad Left | D-Pad Left | D-Pad Left |
| `7` | **RIGHT** | D-Pad Right | D-Pad Right | D-Pad Right | D-Pad Right |
| `8` | **A** (Right) | ○ (Circle) | A | C | A |
| `9` | **X** (Top) | △ (Triangle) | X | Y | — |
| `10` | **L1 / L** | L1 | L | X | — |
| `11` | **R1 / R** | R1 | R | Z | — |
| `12` | **L2** | L2 | — | — | — |
| `13` | **R2** | R2 | — | — | — |
| `14` | **L3** | Left Stick Click | — | — | — |
| `15` | **R3** | Right Stick Click | — | — | — |

---

## 🛠️ Building & Running

### Prerequisites
* JDK 17+
* Android SDK (API Level 34 / compile target 35, min SDK 30)
* Android NDK & CMake 3.22.1+

### Build from Command Line
```bash
cd android

# Run unit tests
./gradlew test

# Build debug APK
./gradlew assembleDebug

# Build release APK
./gradlew assembleRelease
```

The compiled APK will be located at:
`android/app/build/outputs/apk/debug/app-debug.apk`

---

## 🏗️ Architecture

```
kotlin-only/
├── .github/workflows/
│   └── android.yml                      # CI/CD automated test & build pipeline
├── android/
│   ├── app/src/main/
│   │   ├── cpp/
│   │   │   ├── CMakeLists.txt           # Native NDK build definition
│   │   │   ├── libretro-frontend.cpp    # Libretro core dynamic loader & lifecycle
│   │   │   ├── retro-bridge.cpp         # JNI bridge & standard input dispatcher
│   │   │   ├── miracast-render.cpp      # Direct ANativeWindow software compositor
│   │   │   └── miracast-audio.cpp       # Native audio ring buffer & AAudio output
│   │   ├── java/.../ui/
│   │   │   ├── RoleGateScreen.kt        # Mode selector (Host / Player 2 Client)
│   │   │   ├── GamepadDeckScreen.kt     # Dynamic multi-touch gamepad UI
│   │   │   └── CoreRouter.kt            # ROM extension to Libretro core router
│   │   └── kotlin/.../
│   │       ├── MainActivity.kt          # Main lifecycle & physical gamepad dispatcher
│   │       ├── NetworkManager.kt        # NSD discovery & multiplayer TCP mesh
│   │       ├── CastingAdapter.kt        # Miracast DisplayManager presentation API
│   │       └── ThermalManager.kt        # Dynamic device thermal throttle monitor
```

---

## 📄 License

This project is licensed under the terms of the [LICENSE](LICENSE) file.

