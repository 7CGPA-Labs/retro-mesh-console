import Foundation
import Network

@_silgen_name("updatePlayer2Button")
func updatePlayer2Button(_ buttonId: Int32, _ pressed: Bool)

class NetworkManager: NSObject, NetServiceDelegate {
    static let shared = NetworkManager()
    
    private let serviceType = "_retroconsole._tcp."
    private let serviceDomain = "local."
    private let serviceName = "RetroMeshConsoleHost"
    private let port: UInt16 = 48293
    
    // Host properties
    private var netService: NetService?
    private var listener: NWListener?
    private var hostConnection: NWConnection?
    
    // Client properties
    private var serviceBrowser: NetServiceBrowser?
    private var clientConnection: NWConnection?
    
    func startHost() {
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.hostConnection = newConnection
                self?.hostConnection?.start(queue: .global())
                self?.receiveLoop(on: newConnection)
            }
            
            listener?.start(queue: .global())
            
            netService = NetService(domain: serviceDomain, type: serviceType, name: serviceName, port: Int32(port))
            netService?.delegate = self
            netService?.publish()
            print("Host Server and mDNS started")
        } catch {
            print("Failed to start host listener: \(error)")
        }
    }
    
    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, context, isComplete, error in
            if let data = data, data.count == 2 {
                let pressed = data[0] == 1
                let buttonId = Int32(data[1])
                // Call C++ hook
                updatePlayer2Button(buttonId, pressed)
            }
            if error == nil && !isComplete {
                self?.receiveLoop(on: connection)
            }
        }
    }
    
    func startClient() {
        serviceBrowser = NetServiceBrowser()
        serviceBrowser?.delegate = self
        serviceBrowser?.searchForServices(ofType: serviceType, inDomain: serviceDomain)
        print("Searching for Host...")
    }
    
    func sendInput(buttonId: Int, pressed: Bool) {
        let bytes: [UInt8] = [pressed ? 1 : 2, UInt8(buttonId)]
        let data = Data(bytes)
        clientConnection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to send input: \(error)")
            }
        }))
    }
    
    func stop() {
        netService?.stop()
        serviceBrowser?.stop()
        listener?.cancel()
        hostConnection?.cancel()
        clientConnection?.cancel()
    }
}

extension NetworkManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if service.name == serviceName {
            print("Found Host!")
            service.delegate = self
            service.resolve(withTimeout: 5.0)
            browser.stop()
        }
    }
}

extension NetworkManager {
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let data = sender.addresses?.first {
            data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                let sockaddr = pointer.bindMemory(to: sockaddr.self).baseAddress!
                if sockaddr.sa_family == UInt8(AF_INET) {
                    let sockaddr_in = pointer.bindMemory(to: sockaddr_in.self).baseAddress!
                    let ip = String(cString: inet_ntoa(sockaddr_in.sin_addr))
                    print("Connecting to \(ip):\(sender.port)")
                    
                    let host = NWEndpoint.Host(ip)
                    let port = NWEndpoint.Port(rawValue: UInt16(sender.port))!
                    clientConnection = NWConnection(host: host, port: port, using: .tcp)
                    clientConnection?.start(queue: .global())
                }
            }
        }
    }
}
