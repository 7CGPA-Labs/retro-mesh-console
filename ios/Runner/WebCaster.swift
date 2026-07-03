import Foundation
import Network
import CommonCrypto

class WebCaster {
    static let shared = WebCaster()
    
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var isRunning = false
    private let streamingQueue = DispatchQueue(label: "dev.seven_cgpalabs.mojosnap.streaming", qos: .userInteractive)
    
    private let htmlPayload = """
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
    
    func startServer() -> String {
        if isRunning { return currentIPAddress() }
        
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: 8080)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: .global())
            isRunning = true
            set_web_streaming(true)
            
            startStreamingLoop()
            
            return currentIPAddress()
        } catch {
            print("Failed to start WebCaster listener: \(error)")
            return ""
        }
    }
    
    func stopServer() {
        isRunning = false
        set_web_streaming(false)
        listener?.cancel()
        listener = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            if request.contains("Upgrade: websocket") || request.contains("Upgrade: WebSocket") {
                self.handleWebSocketUpgrade(request: request, connection: connection)
            } else {
                self.serveHTML(connection: connection)
            }
        }
    }
    
    private func serveHTML(connection: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(htmlPayload)"
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func handleWebSocketUpgrade(request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: .newlines)
        var wsKey = ""
        for line in lines {
            if line.lowercased().starts(with: "sec-websocket-key:") {
                wsKey = line.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        guard !wsKey.isEmpty else {
            connection.cancel()
            return
        }
        
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let concatenated = wsKey + magic
        guard let data = concatenated.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        
        let acceptHash = Data(digest).base64EncodedString()
        
        let response = "HTTP/1.1 101 Switching Protocols\r\n" +
                       "Upgrade: websocket\r\n" +
                       "Connection: Upgrade\r\n" +
                       "Sec-WebSocket-Accept: \(acceptHash)\r\n\r\n"
        
        connection.send(content: response.data(using: .utf8)!, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.activeConnections.append(connection)
            } else {
                connection.cancel()
            }
        })
    }
    
    private func startStreamingLoop() {
        streamingQueue.async { [weak self] in
            guard let self = self else { return }
            
            while self.isRunning {
                let width = Int(get_web_width())
                let height = Int(get_web_height())
                
                if width > 0 && height > 0, let buffer = get_web_buffer() {
                    let pixelCount = width * height
                    let byteCount = pixelCount * 2
                    
                    var payload = Data()
                    
                    // FIN=1, OPCODE=2
                    payload.append(130)
                    
                    let payloadSize = byteCount + 4
                    if payloadSize <= 125 {
                        payload.append(UInt8(payloadSize))
                    } else if payloadSize <= 65535 {
                        payload.append(126)
                        payload.append(UInt8((payloadSize >> 8) & 0xFF))
                        payload.append(UInt8(payloadSize & 0xFF))
                    } else {
                        payload.append(127)
                        payload.append(contentsOf: [0, 0, 0, 0])
                        payload.append(UInt8((payloadSize >> 24) & 0xFF))
                        payload.append(UInt8((payloadSize >> 16) & 0xFF))
                        payload.append(UInt8((payloadSize >> 8) & 0xFF))
                        payload.append(UInt8(payloadSize & 0xFF))
                    }
                    
                    // Width and Height (little endian)
                    payload.append(UInt8(width & 0xFF))
                    payload.append(UInt8((width >> 8) & 0xFF))
                    payload.append(UInt8(height & 0xFF))
                    payload.append(UInt8((height >> 8) & 0xFF))
                    
                    // Raw pixels
                    let pixelData = Data(bytes: buffer, count: byteCount)
                    payload.append(pixelData)
                    
                    // Send to all active connections
                    let active = self.activeConnections
                    self.activeConnections = []
                    
                    for conn in active {
                        if conn.state == .ready {
                            conn.send(content: payload, completion: .contentProcessed { error in
                                if error != nil {
                                    conn.cancel()
                                }
                            })
                            self.activeConnections.append(conn)
                        }
                    }
                }
                
                usleep(16000) // ~60 FPS
            }
        }
    }
    
    private func currentIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "pdp_ip0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return "http://\(address):8080"
    }
}
