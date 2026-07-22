package dev.seven_cgpalabs.mojosnap.utils

import android.util.Log
import androidx.compose.runtime.mutableStateListOf
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object ConsoleLogger {
    val logs = mutableStateListOf<String>()
    private val formatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    fun log(tag: String, message: String) {
        val timestamp = formatter.format(Date())
        val formatted = "[$timestamp][$tag] $message"
        Log.d("MojoSnap_$tag", message)
        
        // Ensure max 25 lines
        if (logs.size >= 25) {
            logs.removeAt(0)
        }
        logs.add(formatted)
    }
}
