package dev.seven_cgpalabs.mojosnap

import android.util.Base64
import android.util.Log
import java.io.InputStream
import java.io.OutputStream
import java.io.ByteArrayOutputStream
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.zip.Deflater
import java.util.zip.DeflaterOutputStream
import kotlin.concurrent.thread

object WebCaster {
    private const val TAG = "WebCaster"
    private var serverSocket: ServerSocket? = null
    private var isRunning = false
    private var currentIp = ""

    @JvmStatic external fun setWebStreaming(streaming: Boolean)
    @JvmStatic external fun getFrameBuffer(): ByteBuffer
    @JvmStatic external fun getFrameDimensions(): IntArray
    @JvmStatic external fun getRleBuffer(): ByteBuffer
    @JvmStatic external fun getRleSize(): Int
    @JvmStatic external fun waitForNextFrame()
    @JvmStatic external fun getAudioBuffer(): ByteBuffer
    @JvmStatic external fun consumeAudioBuffer(): Int

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

                    var response = "HTTP/1.1 101 Switching Protocols\r\n" +
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
        } catch (e: java.net.SocketException) {
            // Silently ignore client disconnects
        } catch (e: Exception) {
            Log.e(TAG, "Client handler error", e)
        }
    }

    private fun streamFrames(socket: Socket, output: OutputStream) {
        val rleBuffer = getRleBuffer()
        val audioBuffer = getAudioBuffer()
        setWebStreaming(true)
        
        var frameCount = 0
        try {
            while (isRunning && !socket.isClosed) {
                // 1. Send Audio Data
                val aSize = consumeAudioBuffer()
                if (aSize > 0) {
                    val audioBytes = ByteArray(aSize)
                    audioBuffer.position(0)
                    audioBuffer.get(audioBytes, 0, aSize)
                    
                    // Header: type = 1 (audio)
                    output.write(130) // binary frame
                    
                    val payloadSize = aSize + 2 // 1 byte type, 1 byte pad
                    if (payloadSize <= 125) {
                        output.write(payloadSize)
                    } else if (payloadSize <= 65535) {
                        output.write(126)
                        output.write((payloadSize shr 8) and 0xFF)
                        output.write(payloadSize and 0xFF)
                    } else {
                        output.write(127)
                        for (i in 0..3) output.write(0)
                        output.write((payloadSize shr 24) and 0xFF)
                        output.write((payloadSize shr 16) and 0xFF)
                        output.write((payloadSize shr 8) and 0xFF)
                        output.write(payloadSize and 0xFF)
                    }
                    output.write(1) // Audio packet type
                    output.write(0) // Pad for 16-bit alignment in JS
                    output.write(audioBytes)
                    output.flush()
                }

                // 2. Send Video Data (Full 60 FPS Native HW Z-RLE)
                val dims = getFrameDimensions()
                val width = dims[0]
                val height = dims[1]
                val rleSize = getRleSize()
                    
                    if (width > 0 && height > 0 && rleSize > 0) {
                        rleBuffer.position(0)
                        val finalPayload = ByteArray(rleSize)
                        rleBuffer.get(finalPayload, 0, rleSize)
                        
                        output.write(130)
                        
                        val payloadSize = finalPayload.size + 6
                        if (payloadSize <= 125) {
                            output.write(payloadSize)
                        } else if (payloadSize <= 65535) {
                            output.write(126)
                            output.write((payloadSize shr 8) and 0xFF)
                            output.write(payloadSize and 0xFF)
                        } else {
                            output.write(127)
                            for (j in 0..3) output.write(0)
                            output.write((payloadSize shr 24) and 0xFF)
                            output.write((payloadSize shr 16) and 0xFF)
                            output.write((payloadSize shr 8) and 0xFF)
                            output.write(payloadSize and 0xFF)
                        }
                        
                        output.write(0) // Video packet type
                        output.write(0) // Padding
                        
                        val header = ByteArray(4)
                        header[0] = (width and 0xFF).toByte()
                        header[1] = ((width shr 8) and 0xFF).toByte()
                        header[2] = (height and 0xFF).toByte()
                        header[3] = ((height shr 8) and 0xFF).toByte()
                        output.write(header)
                        output.write(finalPayload)
                        output.flush()
                    }
                
                waitForNextFrame()
            }
        } catch (e: Exception) {
            println("WebCaster Client Disconnected: ${e.message}")
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
    body { background: #070714; margin: 0; display: flex; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
    canvas { display: block; }
    #overlay { position: absolute; color: white; font-family: monospace; z-index: 10; cursor: pointer; background: rgba(0,0,0,0.8); padding: 20px; border-radius: 8px;}
  </style>
</head>
<body>
  <div id="overlay">Click to Connect & Unmute Audio</div>
  <canvas id="display"></canvas>
  <script>
    const canvas = document.getElementById('display');
    const gl = canvas.getContext('webgl2', { alpha: false, antialias: false, depth: false });
    const overlay = document.getElementById('overlay');
    let ws;
    let audioCtx;
    let nextAudioTime = 0;
    
    // WebGL Shaders
    const vsSource = `#version 300 es
      in vec2 aPosition;
      in vec2 aTexCoord;
      uniform vec2 uScale;
      out vec2 vTexCoord;
      void main() {
        gl_Position = vec4(aPosition * uScale, 0.0, 1.0);
        vTexCoord = aTexCoord;
      }
    `;
    const fsSource = `#version 300 es
      precision mediump float;
      in vec2 vTexCoord;
      uniform sampler2D uTexture;
      out vec4 fragColor;
      void main() {
        vec4 color = texture(uTexture, vTexCoord);
        // Subtle CRT scanline effect
        float scanline = sin(vTexCoord.y * 800.0) * 0.08;
        color.rgb -= scanline;
        fragColor = vec4(color.rgb, 1.0);
      }
    `;
    
    function compileShader(type, source) {
      const shader = gl.createShader(type);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      return shader;
    }
    
    const program = gl.createProgram();
    gl.attachShader(program, compileShader(gl.VERTEX_SHADER, vsSource));
    gl.attachShader(program, compileShader(gl.FRAGMENT_SHADER, fsSource));
    gl.linkProgram(program);
    gl.useProgram(program);
    
    // Quad Data
    const vertices = new Float32Array([
      -1, -1,  0, 1,
       1, -1,  1, 1,
      -1,  1,  0, 0,
       1,  1,  1, 0,
    ]);
    const vbo = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
    
    const aPosition = gl.getAttribLocation(program, 'aPosition');
    const aTexCoord = gl.getAttribLocation(program, 'aTexCoord');
    const uScale = gl.getUniformLocation(program, 'uScale');
    
    gl.enableVertexAttribArray(aPosition);
    gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 16, 0);
    gl.enableVertexAttribArray(aTexCoord);
    gl.vertexAttribPointer(aTexCoord, 2, gl.FLOAT, false, 16, 8);
    
    // Texture
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    
    let currentWidth = 0;
    let currentHeight = 0;
    
    function updateViewport() {
      if (currentWidth === 0) return;
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
      gl.viewport(0, 0, canvas.width, canvas.height);
      
      const coreAspect = currentWidth / currentHeight;
      const winAspect = canvas.width / canvas.height;
      
      let scaleX = 1.0;
      let scaleY = 1.0;
      
      if (winAspect > coreAspect) {
        scaleX = coreAspect / winAspect;
      } else {
        scaleY = winAspect / coreAspect;
      }
      gl.uniform2f(uScale, scaleX, scaleY);
    }
    
    window.addEventListener('resize', updateViewport);

    overlay.onclick = () => {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
      connect();
    };

    function connect() {
      ws = new WebSocket('ws://' + location.host + '/ws');
      ws.binaryType = 'arraybuffer';
      
      ws.onopen = () => { overlay.style.display = 'none'; };
      ws.onclose = () => { overlay.style.display = 'block'; overlay.innerText = 'Disconnected. Click to Reconnect.'; ws = null; };
      
      let imgData = null;
      let buf8 = null;
      let buf32 = null;

      ws.onmessage = (e) => {
        const data = new DataView(e.data);
        const type = data.getUint8(0);
        
        if (type === 1) { // Audio
            if (!audioCtx) return;
            const int16Data = new Int16Array(e.data, 2);
            const samples = int16Data.length / 2;
            const buffer = audioCtx.createBuffer(2, samples, 44100);
            const left = buffer.getChannelData(0);
            const right = buffer.getChannelData(1);
            for(let i=0; i<samples; i++) {
                left[i] = int16Data[i*2] / 32768.0;
                right[i] = int16Data[i*2+1] / 32768.0;
            }
            const source = audioCtx.createBufferSource();
            source.buffer = buffer;
            source.connect(audioCtx.destination);
            
            // Anti-Drift: Snap to +50ms if we underrun OR if we drift too far into the future!
            if (nextAudioTime < audioCtx.currentTime || nextAudioTime > audioCtx.currentTime + 0.1) {
                nextAudioTime = audioCtx.currentTime + 0.05;
            }
            
            source.start(nextAudioTime);
            nextAudioTime += buffer.duration;
            return;
        }

        if (type === 0) { // Video
            const w = data.getUint16(2, true);
            const h = data.getUint16(4, true);
            
            if (w === 0 || h === 0) return;
            
            if (currentWidth !== w || currentHeight !== h) {
              currentWidth = w;
              currentHeight = h;
              updateViewport();
            }

            const rleBytes = new Uint8Array(e.data, 6);
            const pixels16 = new Uint16Array(w * h);
            let readIdx = 0;
            let writeIdx = 0;
            
            while (readIdx < rleBytes.length && writeIdx < pixels16.length) {
                const c = rleBytes[readIdx++];
                if (c < 128) {
                    const count = c + 1;
                    for (let i = 0; i < count; i++) {
                        pixels16[writeIdx++] = rleBytes[readIdx] | (rleBytes[readIdx+1] << 8);
                        readIdx += 2;
                    }
                } else {
                    const count = (c - 128) + 2;
                    const color = rleBytes[readIdx] | (rleBytes[readIdx+1] << 8);
                    readIdx += 2;
                    for (let i = 0; i < count; i++) {
                        pixels16[writeIdx++] = color;
                    }
                }
            }
            gl.bindTexture(gl.TEXTURE_2D, texture);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB565, w, h, 0, gl.RGB, gl.UNSIGNED_SHORT_5_6_5, pixels16);
            gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        }
      };
    }
  </script>
</body>
</html>
"""
}
