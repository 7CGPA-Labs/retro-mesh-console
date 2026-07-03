package dev.seven_cgpalabs.mojosnap

import android.util.Base64
import android.util.Log
import java.io.InputStream
import java.io.OutputStream
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlin.concurrent.thread

object WebCaster {
    private const val TAG = "WebCaster"
    private var serverSocket: ServerSocket? = null
    private var isRunning = false
    private var currentIp = ""

    // JNI Native Methods
    @JvmStatic external fun setWebStreaming(streaming: Boolean)
    @JvmStatic external fun getFrameBuffer(): ByteBuffer
    @JvmStatic external fun getFrameDimensions(): IntArray

    init {
        try {
            System.loadLibrary("native_render")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Failed to load native library", e)
        }
    }

    fun startServer(): String {
        if (serverSocket != null) return currentIp

        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            var ip = "127.0.0.1"
            for (intf in interfaces) {
                if (intf.name.contains("wlan") || intf.name.contains("en")) {
                    for (addr in intf.inetAddresses) {
                        if (!addr.isLoopbackAddress && addr is Inet4Address) {
                            ip = addr.hostAddress ?: ip
                        }
                    }
                }
            }
            currentIp = "http://$ip:8080"
            serverSocket = ServerSocket(8080)
            isRunning = true

            thread {
                Log.d(TAG, "Server listening on port 8080")
                while (isRunning) {
                    try {
                        val client = serverSocket?.accept() ?: break
                        thread { handleClient(client) }
                    } catch (e: Exception) {
                        if (isRunning) Log.e(TAG, "Accept error", e)
                    }
                }
            }
            return currentIp
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start server", e)
            return ""
        }
    }

    fun stopServer() {
        isRunning = false
        setWebStreaming(false)
        try {
            serverSocket?.close()
        } catch (e: Exception) { }
        serverSocket = null
    }

    private fun handleClient(socket: Socket) {
        try {
            val input = socket.getInputStream()
            val output = socket.getOutputStream()
            val reqBytes = ByteArray(4096)
            val read = input.read(reqBytes)
            if (read <= 0) {
                socket.close()
                return
            }
            
            val request = String(reqBytes, 0, read)
            if (request.contains("Upgrade: websocket", ignoreCase = true)) {
                // Handle WebSocket upgrade
                val keyRegex = "Sec-WebSocket-Key: (.*)".toRegex(RegexOption.IGNORE_CASE)
                val match = keyRegex.find(request)
                if (match != null) {
                    val key = match.groupValues[1].trim()
                    val magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
                    val accept = Base64.encodeToString(MessageDigest.getInstance("SHA-1").digest((key + magic).toByteArray()), Base64.NO_WRAP)

                    val response = "HTTP/1.1 101 Switching Protocols\r\n" +
                                   "Upgrade: websocket\r\n" +
                                   "Connection: Upgrade\r\n" +
                                   "Sec-WebSocket-Accept: $accept\r\n\r\n"
                    output.write(response.toByteArray())
                    output.flush()

                    Log.d(TAG, "WebSocket client connected!")
                    streamFrames(socket, output)
                } else {
                    socket.close()
                }
            } else {
                // Serve HTML payload
                val response = "HTTP/1.1 200 OK\r\n" +
                               "Content-Type: text/html\r\n" +
                               "Connection: close\r\n\r\n" +
                               htmlPayload
                output.write(response.toByteArray())
                output.flush()
                socket.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Client handler error", e)
        }
    }

    private fun streamFrames(socket: Socket, output: OutputStream) {
        val frameBuffer = getFrameBuffer()
        setWebStreaming(true)
        
        try {
            while (isRunning && !socket.isClosed) {
                val dims = getFrameDimensions()
                val width = dims[0]
                val height = dims[1]
                
                if (width > 0 && height > 0) {
                    val pixelCount = width * height
                    val byteCount = pixelCount * 2
                    
                    // WebSocket binary frame header
                    // FIN=1, OPCODE=2 (binary)
                    output.write(130)
                    
                    val payloadSize = byteCount + 4 // 4 bytes for dimensions header
                    if (payloadSize <= 125) {
                        output.write(payloadSize)
                    } else if (payloadSize <= 65535) {
                        output.write(126)
                        output.write((payloadSize shr 8) and 0xFF)
                        output.write(payloadSize and 0xFF)
                    } else {
                        output.write(127)
                        output.write(0); output.write(0); output.write(0); output.write(0);
                        output.write((payloadSize shr 24) and 0xFF)
                        output.write((payloadSize shr 16) and 0xFF)
                        output.write((payloadSize shr 8) and 0xFF)
                        output.write(payloadSize and 0xFF)
                    }
                    
                    // Header: Width (2), Height (2) little endian
                    val header = ByteArray(4)
                    header[0] = (width and 0xFF).toByte()
                    header[1] = ((width shr 8) and 0xFF).toByte()
                    header[2] = (height and 0xFF).toByte()
                    header[3] = ((height shr 8) and 0xFF).toByte()
                    output.write(header)
                    
                    // Pixels from DirectByteBuffer
                    frameBuffer.position(0)
                    val frameBytes = ByteArray(byteCount)
                    frameBuffer.get(frameBytes, 0, byteCount)
                    output.write(frameBytes)
                    output.flush()
                }
                
                // Sleep for ~60fps
                Thread.sleep(16)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Streaming disconnected")
        } finally {
            setWebStreaming(false)
            try { socket.close() } catch (e: Exception) {}
        }
    }

    private const val htmlPayload = """
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Mojo Snap Console</title>
  <style>
    body { background: black; margin: 0; display: flex; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
    canvas { max-width: 100%; max-height: 100%; object-fit: contain; image-rendering: pixelated; }
    #overlay { position: absolute; color: white; font-family: monospace; }
  </style>
</head>
<body>
  <div id="overlay">Connecting...</div>
  <canvas id="display"></canvas>
  <script>
    const canvas = document.getElementById('display');
    const ctx = canvas.getContext('2d', { alpha: false });
    const overlay = document.getElementById('overlay');
    let ws;

    function connect() {
      ws = new WebSocket('ws://' + location.host + '/ws');
      ws.binaryType = 'arraybuffer';
      
      ws.onopen = () => { overlay.style.display = 'none'; };
      ws.onclose = () => { overlay.style.display = 'block'; overlay.innerText = 'Disconnected. Reconnecting...'; setTimeout(connect, 2000); };
      
      let imgData = null;
      let buf8 = null;
      let buf32 = null;

      ws.onmessage = (e) => {
        const data = new DataView(e.data);
        const w = data.getUint16(0, true);
        const h = data.getUint16(2, true);
        
        if (canvas.width !== w || canvas.height !== h) {
          canvas.width = w;
          canvas.height = h;
          imgData = ctx.createImageData(w, h);
          buf8 = new Uint8ClampedArray(imgData.data.buffer);
          buf32 = new Uint32Array(imgData.data.buffer);
        }

        const pixels16 = new Uint16Array(e.data, 4);
        for (let i = 0; i < pixels16.length; i++) {
          const p = pixels16[i];
          const r = ((p >> 11) & 0x1F) << 3;
          const g = ((p >> 5) & 0x3F) << 2;
          const b = (p & 0x1F) << 3;
          buf32[i] = (255 << 24) | (b << 16) | (g << 8) | r;
        }
        
        imgData.data.set(buf8);
        ctx.putImageData(imgData, 0, 0);
      };
    }
    connect();
  </script>
</body>
</html>
"""
}
