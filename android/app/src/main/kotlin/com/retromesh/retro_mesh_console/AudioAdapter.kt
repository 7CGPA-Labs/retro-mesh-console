package com.retromesh.retro_mesh_console

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioAdapter(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val methodChannel = MethodChannel(messenger, "com.retromesh.console/audio")
    private var audioTrack: AudioTrack? = null

    init {
        methodChannel.setMethodCallHandler(this)
        initAudioTrack()
    }

    private fun initAudioTrack() {
        val sampleRate = 44100
        val bufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_STEREO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize * 4)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
            
        audioTrack?.play()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pushAudio") {
            val bytes = call.arguments as? ByteArray
            if (bytes != null) {
                audioTrack?.write(bytes, 0, bytes.size, AudioTrack.WRITE_NON_BLOCKING)
            }
            result.success(null)
        } else {
            result.notImplemented()
        }
    }
    
    fun release() {
        audioTrack?.stop()
        audioTrack?.release()
    }
}
