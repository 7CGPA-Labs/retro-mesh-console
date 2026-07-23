import Foundation
import Network

@_silgen_name("updatePlayer2Button")
func updatePlayer2Button(_ buttonId: Int32, _ pressed: Bool)

class NetworkManager: NSObject, NetServiceDelegate {
    static let shared = NetworkManager()
    
    private let serviceType = "_retroconsole._tcp."
    private let serviceDomain = "local."
    private let serviceNamePrefix = "MojoSnapConsoleHost"
    private let port: UInt16 = 48293
    
    // Host properties
    private var netService: NetService?
    private var listener: NWListener?
    private var hostConnection: NWConnection?
    
    // Client properties
    private var serviceBrowser: NetServiceBrowser?
    private var clientConnection: NWConnection?
    
    var onHostsDiscovered: (([[String: Any]]) -> Void)?
    var onHostDisconnected: (() -> Void)?
    private var discoveredHosts: [[String: Any]] = []
    
    func startHost(coreName: String, playerName: String) {
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.hostConnection = newConnection
                self?.hostConnection?.start(queue: .global())
                self?.receiveLoop(on: newConnection)
            }
            
            listener?.start(queue: .global())
            
            netService = NetService(domain: serviceDomain, type: serviceType, name: "MojoSnap - \(playerName)", port: Int32(port))
            let txtData = NetService.data(fromTXTRecord: ["core": coreName.data(using: .utf8)!])
            netService?.setTXTRecord(txtData)
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
            } else {
                print("Host connection closed or error")
            }
        }
    }
    
    func startDiscovery() {
        discoveredHosts.removeAll()
        onHostsDiscovered?(discoveredHosts)
        serviceBrowser = NetServiceBrowser()
        serviceBrowser?.delegate = self
        serviceBrowser?.searchForServices(ofType: serviceType, inDomain: serviceDomain)
        print("Searching for Hosts...")
    }
    
    func stopDiscovery() {
        serviceBrowser?.stop()
        serviceBrowser = nil
    }
    
    func connectToServer(ip: String) {
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(rawValue: self.port)!
        clientConnection = NWConnection(host: host, port: port, using: .tcp)
        
        clientConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connected to server")
                self?.clientReceiveLoop(on: self!.clientConnection!)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.onHostDisconnected?()
            case .cancelled:
                print("Connection cancelled")
                self?.onHostDisconnected?()
            default:
                break
            }
        }
        clientConnection?.start(queue: .global())
    }
    
    private func clientReceiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, context, isComplete, error in
            if isComplete || error != nil {
                print("Client disconnected from server")
                self?.onHostDisconnected?()
            } else {
                self?.clientReceiveLoop(on: connection)
            }
        }
    }
    
    private let sendQueue = DispatchQueue(label: "dev.seven_cgpalabs.mojosnap.sendQueue")
    private var sendBuffer = [UInt8](repeating: 0, count: 2)

    func sendInput(buttonId: Int, pressed: Bool) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            self.sendBuffer[0] = pressed ? 1 : 2
            self.sendBuffer[1] = UInt8(buttonId)
            let data = Data(self.sendBuffer)
            self.clientConnection?.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    print("Failed to send input: \(error)")
                }
            }))
        }
    }
    
    func stop() {
        stopDiscovery()
        netService?.stop()
        listener?.cancel()
        hostConnection?.cancel()
        clientConnection?.cancel()
    }
}

extension NetworkManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if service.name.contains(serviceNamePrefix) {
            print("Found Host: \(service.name)")
            service.delegate = self
            service.resolve(withTimeout: 5.0)
        }
    }
}

extension NetworkManager {
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let data = sender.addresses?.first {
            data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                let sockaddr = pointer.bindMemory(to: sockaddr.self).baseAddress!
                if sockaddr.pointee.sa_family == UInt8(AF_INET) {
                    let sockaddr_in_ptr = pointer.bindMemory(to: sockaddr_in.self).baseAddress!
                    let ip = String(cString: inet_ntoa(sockaddr_in_ptr.pointee.sin_addr))
                    
                    var coreName = "nes"
                    if let txtData = sender.txtRecordData() {
                        let txtDict = NetService.dictionary(fromTXTRecord: txtData)
                        if let coreData = txtDict["core"], let c = String(data: coreData, encoding: .utf8) {
                            coreName = c
                        }
                    }
                    
                    let hostMap: [String: Any] = [
                        "ip": ip,
                        "name": sender.name,
                        "core": coreName
                    ]
                    discoveredHosts.append(hostMap)
                    onHostsDiscovered?(discoveredHosts)
                }
            }
        }
    }
}
