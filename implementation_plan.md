# Mojo Snap: RGUI-Style Console Menu & Graphics Settings
**Implementation Plan**

This document outlines the step-by-step roadmap for building out a robust, RGUI-style console menu that features dynamic graphics settings (like fixing large-display texture blurring) and dynamic core options.

---

## Phase 1: Native Bridge Upgrades (The Backend)
To support changing graphics and core settings on the fly, our native layers need to accept commands from Flutter.

**1. Dynamic Video Filtering Toggle:**
*   **Android:** Expose a new JNI/FFI function `set_video_filtering(bool isLinear)` in `miracast-render.cpp`. When called, it binds the active OpenGL texture and updates the `GL_TEXTURE_MAG_FILTER` and `GL_TEXTURE_MIN_FILTER` on the fly to switch between `GL_NEAREST` (Sharp) and `GL_LINEAR` (Smooth).
*   **iOS:** Expose a similar FFI function in `miracast-render.mm` that dynamically sets `global_tv_layer.magnificationFilter = isLinear ? kCAFilterLinear : kCAFilterNearest`.

**2. Core Options Environment Hooks:**
*   In Libretro, emulation cores expose their internal settings (like Game Boy color palettes or N64 resolution hacks) via the environment callbacks: `RETRO_ENVIRONMENT_GET_VARIABLE` and `RETRO_ENVIRONMENT_SET_VARIABLES`.
*   Upgrade our C++ `native_environment_cb` to parse these variables into a structured format, pass them up to Dart via FFI, and allow Dart to update them and trigger a refresh.

---

## Phase 2: State Management & Persistence
**1. Settings Service:** 
Implement a lightweight `SettingsManager` in Flutter (using `shared_preferences`) to persist the user's configuration across sessions. 
*   `video_filter`: Sharp (Nearest) vs Smooth (Linear)
*   `state_slot`: The current save-state slot (0-9)
*   `core_specific_options`: A dictionary of saved core variables.

---

## Phase 3: Console Menu UI Overhaul (The Frontend)
Expand the simple "MENU" button popup in `gamepad_deck.dart` into a nested, tabbed or paginated menu system heavily inspired by RetroArch's RGUI.

### Menu Structure
*   **Quick Menu (Default Screen)**
    *   `Resume Game`
    *   `Restart Game` *(Uses the existing FFI `retro_reset()`)*
    *   `Close Content` *(Shuts down engine and returns to ROM picker)*
    *   `State Slot:` `< 1 >` *(Increment/decrement active slot)*
    *   `Save State`
    *   `Load State`

*   **Settings Menu**
    *   **Graphics & Video:**
        *   `Scaling Filter:` **Sharp (Nearest Neighbor)** / **Smooth (Bilinear)**
        *   `Aspect Ratio:` **Core Provided** / **Stretch to Fill**
    *   **Audio:**
        *   `Mute Audio`

*   **Core Options Menu**
    *   A dynamically generated list of settings specifically queried from the running Libretro core (e.g., Palette options for Game Boy, SuperFX overclock options for SNES).

---

## Phase 4: Integration & Polish
**1. Controller Navigation:** 
Ensure the menu can be navigated entirely using the virtual D-Pad and A/B buttons on the host gamepad (just like real RGUI), in addition to standard touch scrolling.

**2. Pause Logic Integration:** 
Ensure that opening sub-menus respects the `_setNativeEmulatorPaused(true)` state, so the game remains completely frozen in the background while tweaking graphics or core options.

---

## Phase 5: Physical Controller Auto-Morphing (Bluetooth & 2.4G)
To provide the ultimate ergonomic experience for complex systems like PS1 (which requires analog sticks and L1/L2/R1/R2) and DOSBox (which relies heavily on keyboard/mouse mappings), the app will implement a smart fallback system for physical controllers.

**1. Universal Hardware Detection:**
*   **Bluetooth Controllers:** Automatically detect when a user pairs a DualSense, Xbox Wireless, or 8BitDo controller.
*   **2.4G Controllers (OTG):** Automatically detect when a 2.4GHz receiver dongle is plugged into the device's USB-C port via an OTG adapter (registered by Android/iOS as a standard USB HID Gamepad).

**2. UI "Auto-Morphing":**
*   **Virtual Pad Fade-out:** The moment a physical controller is detected, smoothly fade out the virtual touch buttons from the screen to free up visual space.
*   **Smart Telemetry Hub:** Morph the phone's touch interface into a clean "Command Center" that displays connection health, battery status, quick-save slots, and the active console menu, shifting the heavy lifting of gameplay entirely to the physical pad.
*   **Seamless Fallback:** If the controller disconnects or the dongle is unplugged, instantly restore the virtual touch controller so the user never loses control.
