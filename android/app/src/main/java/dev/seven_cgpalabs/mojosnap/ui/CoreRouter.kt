package dev.seven_cgpalabs.mojosnap.ui

object CoreRouter {
    private val extensionToCore = mapOf(
        "nes" to "fceumm",
        "smc" to "snes9x",
        "sfc" to "snes9x",
        "md" to "genesis_plus_gx",
        "sms" to "genesis_plus_gx",
        "gg" to "genesis_plus_gx",
        "gba" to "mgba",
        "bin" to "pcsx_rearmed",
        "cue" to "pcsx_rearmed",
        "iso" to "pcsx_rearmed",
        "img" to "pcsx_rearmed",
        "exe" to "dosbox_pure",
        "bat" to "dosbox_pure",
        "com" to "dosbox_pure",
        "zip" to "dosbox_pure",
        "gb" to "gambatte",
        "gbc" to "gambatte"
    )

    fun getSupportedExtensions(): List<String> {
        return extensionToCore.keys.toList()
    }

    fun resolveCore(romPath: String): String {
        val ext = romPath.substringAfterLast('.').lowercase()
        val corePrefix = extensionToCore[ext] ?: "fceumm"
        return "${corePrefix}_libretro_android.so"
    }
}
